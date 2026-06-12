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
    var fetchedAt: Date
}

enum UsageError: Error {
    case noToken          // not logged in, or this app lacks keychain access
    case unauthorized     // token expired/invalid
    case rateLimited      // 429 — back off
    case transport        // network/parse failure
}

/// Reads Claude Code usage straight from the endpoint the official client uses
/// (`/usage`, and the VSCode/Cursor extension's own usage display). Same OAuth
/// token from the login keychain, same first-party endpoint — nothing here that
/// the editor isn't already doing.
enum UsageClient {
    /// Sent as `claude-code/<version>`; the endpoint throttles generic agents.
    static let clientVersion = "2.1.168"

    static func fetch() async -> Result<Usage, UsageError> {
        guard let token = readToken() else { return .failure(.noToken) }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.timeoutInterval = 10
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/\(clientVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse
        else { return .failure(.transport) }

        switch http.statusCode {
        case 200: break
        case 401, 403: return .failure(.unauthorized)
        case 429: return .failure(.rateLimited)
        default: return .failure(.transport)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return .failure(.transport) }
        return .success(Usage(
            fiveHour: window(from: json["five_hour"]),
            sevenDay: window(from: json["seven_day"]),
            fetchedAt: Date()))
    }

    // MARK: - Keychain

    /// The Claude Code login token, stored as a generic password under service
    /// "Claude Code-credentials". Reading another app's item prompts for consent
    /// on first launch ("Always Allow" makes it stick); falls back to
    /// ~/.claude/.credentials.json if present (headless/Linux-style installs).
    private static func readToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data, let token = accessToken(from: data) {
            return token
        }
        let fileURL = URL(fileURLWithPath:
            NSString(string: "~/.claude/.credentials.json").expandingTildeInPath)
        if let data = try? Data(contentsOf: fileURL), let token = accessToken(from: data) {
            return token
        }
        return nil
    }

    private static func accessToken(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { return nil }
        return token
    }

    // MARK: - Parsing

    private static func window(from value: Any?) -> UsageWindow? {
        guard let dict = value as? [String: Any],
              let utilization = dict["utilization"] as? Double
        else { return nil }
        return UsageWindow(utilization: utilization, resetsAt: date(from: dict["resets_at"]))
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
