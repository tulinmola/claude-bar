import Foundation
import Security

struct UsageWindow {
    var utilization: Double
    var resetsAt: Date?

    /// Percentage to show now. Past the reset boundary the real utilization is
    /// back to zero, which covers the gap between a reset and the next poll.
    func effectivePercentage(at now: Date) -> Double {
        if let resetsAt, now >= resetsAt { return 0 }
        return min(max(utilization, 0), 100)
    }
}

struct Usage {
    var fiveHour: UsageWindow?
    var sevenDay: UsageWindow?
    var scopedWeekly: UsageWindow?   // per-model weekly sublimit, e.g. Fable
    var scopedName: String?          // what it's scoped to, per the API
    var plan: String?      // subscription tier from the token, e.g. "max"
    var fetchedAt: Date
}

enum UsageError: Error {
    case noToken          // not logged in, or this app lacks keychain access
    case unauthorized     // token expired/invalid
    case rateLimited(retryAfter: TimeInterval?)   // 429 — back off
    case transport        // network/parse failure
}

/// Reads Claude Code usage straight from the endpoint the official client uses
/// (`/usage`, and the VSCode/Cursor extension's own usage display). Same OAuth
/// token from the login keychain, same first-party endpoint — nothing here that
/// the editor isn't already doing.
enum UsageClient {
    /// Sent as `claude-code/<version>`; the endpoint throttles generic agents.
    /// Resolved from the installed client rather than pinned, because a version
    /// frozen at build time only drifts further from the real one the longer the
    /// app runs. Cheap enough to redo per fetch: a couple of small file reads
    /// every few minutes, next to an HTTPS round trip.
    static var clientVersion: String { installedVersion() ?? fallbackVersion }

    /// Used when no install can be located — a real version, so the header still
    /// looks like the client rather than something the endpoint has never seen.
    static let fallbackVersion = "2.1.235"

    /// npm puts `package.json` next to the code; the local installer and the two
    /// usual npm prefixes cover how Claude Code actually lands on a Mac. The
    /// npm-global updater also records the version it last moved to, which is a
    /// close-enough answer when none of the package paths exist.
    private static func installedVersion() -> String? {
        let packages = [
            "~/.claude/local/node_modules/@anthropic-ai/claude-code/package.json",
            "/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/package.json",
            "/usr/local/lib/node_modules/@anthropic-ai/claude-code/package.json",
        ]
        for path in packages {
            if let version = string(atPath: path, key: "version") { return version }
        }
        return string(atPath: "~/.claude/.last-update-result.json", key: "version_to")
    }

    private static func string(atPath path: String, key: String) -> String? {
        let url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = json[key] as? String, !value.isEmpty
        else { return nil }
        return value
    }

    /// The credentials, once we've managed to read them. Reading the keychain is
    /// what triggers macOS's consent prompt, and this app doesn't own the item —
    /// Claude Code does, and rewrites it as it refreshes the token. So we hold
    /// what we read and go back to the keychain only when the token stops
    /// working, rather than on all ~280 polls a day.
    @MainActor private static var cached: (token: String, plan: String?)?

    @MainActor
    static func fetch() async -> Result<Usage, UsageError> {
        // A 401 means the token rotated under us: drop it and read the keychain
        // once more — the single call in here that can put a prompt on screen.
        if let creds = cached {
            let result = await fetch(using: creds)
            if case .failure(.unauthorized) = result {
                cached = nil
            } else {
                return result
            }
        }
        guard let creds = readCredentials() else { return .failure(.noToken) }
        cached = creds
        return await fetch(using: creds)
    }

    private static func fetch(
        using creds: (token: String, plan: String?)
    ) async -> Result<Usage, UsageError> {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.timeoutInterval = 10
        request.setValue("Bearer \(creds.token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/\(clientVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse
        else { return .failure(.transport) }

        switch http.statusCode {
        case 200: break
        case 401, 403: return .failure(.unauthorized)
        case 429: return .failure(.rateLimited(retryAfter: retryAfter(from: http)))
        default: return .failure(.transport)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return .failure(.transport) }
        let scoped = scopedWeekly(from: json["limits"])
        return .success(Usage(
            fiveHour: window(from: json["five_hour"]),
            sevenDay: window(from: json["seven_day"]),
            scopedWeekly: scoped?.window,
            scopedName: scoped?.name,
            plan: creds.plan,
            fetchedAt: Date()))
    }

    /// `Retry-After` in seconds. The spec allows an HTTP-date too, but the
    /// endpoint sends the delta form; anything else falls through to the
    /// caller's own backoff, which is the safer default anyway.
    private static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = TimeInterval(raw.trimmingCharacters(in: .whitespaces)),
              seconds > 0
        else { return nil }
        return seconds
    }

    // MARK: - Keychain

    /// The Claude Code login token (plus subscription tier), stored as a generic
    /// password under service "Claude Code-credentials". Reading another app's
    /// item prompts for consent on first launch ("Always Allow" makes it stick);
    /// falls back to ~/.claude/.credentials.json (headless/Linux-style installs).
    private static func readCredentials() -> (token: String, plan: String?)? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data, let creds = credentials(from: data) {
            return creds
        }
        let fileURL = URL(fileURLWithPath:
            NSString(string: "~/.claude/.credentials.json").expandingTildeInPath)
        if let data = try? Data(contentsOf: fileURL), let creds = credentials(from: data) {
            return creds
        }
        return nil
    }

    private static func credentials(from data: Data) -> (token: String, plan: String?)? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { return nil }
        return (token, oauth["subscriptionType"] as? String)
    }

    /// Reads the signed-in account email from Claude Code's ~/.claude.json (a
    /// plain file — no keychain access, no prompt).
    static func accountEmail() -> String? {
        let url = URL(fileURLWithPath:
            NSString(string: "~/.claude.json").expandingTildeInPath)
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = json["oauthAccount"] as? [String: Any],
              let email = account["emailAddress"] as? String, !email.isEmpty
        else { return nil }
        return email
    }

    // MARK: - Parsing

    private static func window(from value: Any?) -> UsageWindow? {
        guard let dict = value as? [String: Any],
              let utilization = dict["utilization"] as? Double
        else { return nil }
        return UsageWindow(utilization: utilization, resetsAt: date(from: dict["resets_at"]))
    }

    /// The per-model weekly sublimit (e.g. Fable), from the newer `limits`
    /// array — the old top-level `seven_day_opus`/`_sonnet` keys are all null
    /// now. Matched on `kind` rather than the model name, so a rename doesn't
    /// silently blank the bar; the API's own `display_name` becomes the label.
    /// Only the first scoped limit is used — accounts have one today.
    private static func scopedWeekly(from value: Any?) -> (window: UsageWindow, name: String)? {
        guard let limits = value as? [[String: Any]],
              let limit = limits.first(where: { $0["kind"] as? String == "weekly_scoped" }),
              let percent = number(from: limit["percent"])
        else { return nil }
        let window = UsageWindow(utilization: percent, resetsAt: date(from: limit["resets_at"]))
        return (window, modelName(from: limit["scope"]) ?? "Scoped")
    }

    /// "Fable" from a model-scoped limit. Surface-scoped limits exist in the
    /// schema but we've never seen one populated, so rather than guess at its
    /// shape they fall back to the generic "Scoped" label.
    private static func modelName(from value: Any?) -> String? {
        guard let scope = value as? [String: Any],
              let model = scope["model"] as? [String: Any],
              let display = model["display_name"] as? String, !display.isEmpty
        else { return nil }
        return display
    }

    /// `percent` arrives as an integer where `utilization` is a real.
    private static func number(from value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        return nil
    }

    /// `resets_at` is ISO 8601 with fractional seconds (e.g.
    /// "2026-06-12T11:10:00.121609+00:00"); tolerate epoch numbers too.
    private static func date(from value: Any?) -> Date? {
        switch value {
        case let seconds as Double:
            return Date(timeIntervalSince1970: seconds > 1e12 ? seconds / 1000 : seconds)
        case let string as String:
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso.date(from: string) { return date }
            iso.formatOptions = [.withInternetDateTime]
            return iso.date(from: string)
        default:
            return nil
        }
    }
}
