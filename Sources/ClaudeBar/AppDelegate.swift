import AppKit
import ServiceManagement

/// Polls the usage endpoint on a steady run-loop timer, plus an immediate
/// refresh on launch, on wake-from-sleep, and when the menu is opened. The
/// timer fires only while the Mac is awake (user-space timers never wake a
/// sleeping Mac — they fire on the next wake), so it keeps the bars current
/// without ever disturbing sleep. Idle CPU between polls is negligible.
///
/// Every one of those triggers funnels through `refresh()`, which is the only
/// thing that talks to the network and the only place the spacing floor and the
/// 429 backoff are enforced. There is deliberately no bypass: the endpoint
/// throttles on the requests it receives, not on why we sent them.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    /// Poll cadence. Rate limits move over 5h/7d windows, so this is plenty —
    /// and it leaves real margin under the ~3 min the endpoint starts throttling
    /// at, rather than sitting exactly on the boundary the way 180s did.
    private let pollInterval: TimeInterval = 300
    /// Don't issue a network call more often than this, however many events fire.
    private let minFetchSpacing: TimeInterval = 45
    /// Ceiling on the 429 backoff, so a stuck or bogus `Retry-After` can't park
    /// the bars indefinitely — we re-test at worst hourly.
    private let maxBackoff: TimeInterval = 3600
    /// Lengths of the windows the endpoint reports. The per-model sublimit
    /// shares the weekly window (and its reset time).
    private let sessionLength: TimeInterval = 5 * 3600
    private let weekLength: TimeInterval = 7 * 24 * 3600

    private var statusItem: NSStatusItem!
    private var pollTimer: Timer?
    private var activityToken: NSObjectProtocol?
    private var usage: Usage?
    private var accountEmail: String?
    private var lastError: UsageError?
    /// Earliest moment the next network call may go out — moved forward by the
    /// spacing floor after every attempt, and much further out after a 429.
    private var nextAllowedFetch = Date.distantPast
    private var backoffStep = 0
    private var isFetching = false
    private var lastDrawn: [Int?]?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        render()

        accountEmail = UsageClient.accountEmail()
        refresh()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification, object: nil)

        // A plain run-loop timer fires reliably while the Mac is awake, unlike a
        // discretionary background activity that the OS defers on battery. It is
        // added to the main run loop, so the block runs on the main actor.
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = pollInterval / 6
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        // Opt out of App Nap, which would otherwise throttle the timer on a
        // background accessory app. This still allows the system to sleep
        // normally — it only keeps us from being napped while awake.
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Keep the Claude usage meter current")
    }

    @objc private func didWake() {
        accountEmail = UsageClient.accountEmail()
        refresh()
    }

    // MARK: - Fetch

    /// Fetches unless a call is already in flight, we're inside the spacing
    /// floor, or we're serving out a 429 backoff.
    private func refresh() {
        guard !isFetching, Date() >= nextAllowedFetch else { return }
        isFetching = true
        nextAllowedFetch = Date().addingTimeInterval(minFetchSpacing)
        Task { [weak self] in
            let result = await UsageClient.fetch()
            guard let self else { return }
            self.isFetching = false
            switch result {
            case .success(let usage):
                self.usage = usage
                self.lastError = nil
                self.backoffStep = 0
            case .failure(let error):
                self.lastError = error   // keep last-good usage on screen
                if case .rateLimited(let retryAfter) = error {
                    self.backOff(retryAfter: retryAfter)
                }
            }
            self.render()
        }
    }

    /// Wait longer after a 429: the endpoint's own `Retry-After` when it sends
    /// one, otherwise doubling from a poll interval up to `maxBackoff`. Without
    /// this the timer kept knocking at exactly the cadence that got us
    /// throttled, which is what turned a brief 429 into a lasting one.
    private func backOff(retryAfter: TimeInterval?) {
        backoffStep = min(backoffStep + 1, 8)
        let doubling = pollInterval * pow(2, Double(backoffStep - 1))
        nextAllowedFetch = Date().addingTimeInterval(min(retryAfter ?? doubling, maxBackoff))
    }

    // MARK: - Rendering

    private func render() {
        let now = Date()
        var bars = [
            bar(usage?.fiveHour, length: sessionLength, at: now),
            bar(usage?.sevenDay, length: weekLength, at: now),
        ]
        // Only takes a third slot on accounts that actually have a per-model
        // sublimit; otherwise the two bars re-center.
        if let scoped = usage?.scopedWeekly {
            bars.append(bar(scoped, length: weekLength, at: now))
        }
        // Redraw only when a rounded value changes. The count changes too if
        // the sublimit appears or disappears, which counts as a change.
        let rounded = bars.flatMap {
            [$0.percentage.map { Int($0.rounded()) }, $0.elapsed.map { Int($0.rounded()) }]
        }
        if rounded != lastDrawn {
            lastDrawn = rounded
            statusItem.button?.image = IconRenderer.icon(bars: bars)
        }
    }

    /// A window as the icon wants it: what you've spent, and how far into the
    /// window we are.
    private func bar(
        _ window: UsageWindow?, length: TimeInterval, at now: Date
    ) -> IconRenderer.Bar {
        IconRenderer.Bar(
            percentage: window?.effectivePercentage(at: now),
            elapsed: elapsedPercent(window, length: length, at: now))
    }

    /// How far into a window we are, 0–100. nil when there's no data or the
    /// window has already elapsed.
    private func elapsedPercent(_ window: UsageWindow?, length: TimeInterval, at now: Date) -> Double? {
        guard let reset = window?.resetsAt else { return nil }
        let remaining = reset.timeIntervalSince(now)
        guard remaining > 0, remaining <= length else { return nil }
        return (1 - remaining / length) * 100
    }

    // MARK: - Menu

    func menuWillOpen(_ menu: NSMenu) {
        refresh()   // exact read when you look, throttled
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let now = Date()

        if let account = accountLine() {
            menu.addItem(disabledItem(account))
            menu.addItem(.separator())
        }

        menu.addItem(usageItem(
            label: "Session (5h)", window: usage?.fiveHour, length: sessionLength, now: now))
        menu.addItem(usageItem(
            label: "Weekly (7d)", window: usage?.sevenDay, length: weekLength, now: now))
        if let scoped = usage?.scopedWeekly {
            menu.addItem(usageItem(
                label: "\(usage?.scopedName ?? "Scoped") (7d)",
                window: scoped, length: weekLength, now: now))
        }
        menu.addItem(disabledItem(statusText(now: now)))

        menu.addItem(.separator())
        let refreshItem = NSMenuItem(
            title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        if Bundle.main.bundleURL.pathExtension == "app" {
            let login = NSMenuItem(
                title: "Start at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
            login.target = self
            login.state = SMAppService.mainApp.status == .enabled ? .on : .off
            menu.addItem(login)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit Claude Bar",
            action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    /// "email · Max" for the signed-in account, or nil when unknown.
    private func accountLine() -> String? {
        guard let email = accountEmail else { return nil }
        if let plan = usage?.plan, !plan.isEmpty {
            return "\(email) · \(plan.capitalized)"
        }
        return email
    }

    private func statusText(now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        switch lastError {
        case .noToken:
            return "Sign in with Claude Code to enable"
        case .unauthorized:
            return "Token expired — open Claude Code once"
        case .rateLimited:
            // Name the moment, because while we're backing off "Refresh Now" is
            // a no-op — saying "later" just invites clicking it.
            return "Rate limited — retrying \(formatter.localizedString(for: nextAllowedFetch, relativeTo: now))"
        case .transport:
            return usage == nil ? "Can't reach Anthropic" : "Offline — showing last data"
        case nil:
            guard let fetchedAt = usage?.fetchedAt else { return "Loading…" }
            return "Updated \(formatter.localizedString(for: fetchedAt, relativeTo: now))"
        }
    }

    /// A drawn meter row. Falls back to plain text when there's nothing to
    /// draw, so an unavailable window doesn't leave an empty chart.
    private func usageItem(
        label: String, window: UsageWindow?, length: TimeInterval, now: Date
    ) -> NSMenuItem {
        guard let window else { return disabledItem("\(label): no data") }
        let elapsed = elapsedPercent(window, length: length, at: now)
        let item = NSMenuItem()
        item.view = UsageRowView(
            title: label,
            percentage: window.effectivePercentage(at: now),
            elapsed: elapsed,
            detail: detailText(window, elapsed: elapsed, now: now))
        return item
    }

    /// "24% elapsed · resets sáb, 19:59" — the rest of what the old one-line
    /// row carried, now that the percentage has a slot of its own.
    private func detailText(_ window: UsageWindow, elapsed: Double?, now: Date) -> String {
        var parts: [String] = []
        if let elapsed {
            parts.append(String(format: "%.0f%% elapsed", elapsed))
        }
        if let resetsAt = window.resetsAt, resetsAt > now {
            parts.append("resets \(resetDescription(resetsAt, now: now))")
        }
        return parts.joined(separator: " · ")
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        NSMenuItem(title: title, action: nil, keyEquivalent: "")
    }

    /// The exact moment a window resets, rather than a vague "in 5d": today's
    /// resets show just the clock, later ones prepend the weekday. Built from a
    /// localized template, so the field order, separator, and 12- vs 24-hour
    /// clock all follow the user's locale.
    ///
    /// Rounded to the minute first. The endpoint reports the boundary
    /// end-exclusive and recomputes it per call, so it arrives a few hundred
    /// milliseconds either side of the round minute (12:59:59.96Z one poll,
    /// 13:00:00.02Z the next) — truncating would flip the displayed time
    /// between 14:59 and 15:00 on every refresh. The round minute is the real
    /// boundary anyway.
    private func resetDescription(_ date: Date, now: Date) -> String {
        let rounded = Date(timeIntervalSinceReferenceDate:
            (date.timeIntervalSinceReferenceDate / 60).rounded() * 60)
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate(
            date.timeIntervalSince(now) < 23 * 3600 ? "jmm" : "EEEjmm")
        return formatter.string(from: rounded)
    }

    @objc private func refreshNow() { refresh() }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Login item toggle failed: \(error)")
        }
    }
}
