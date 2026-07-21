import Foundation

public struct AppConfiguration: Equatable, Sendable {
    public enum ConfigurationError: LocalizedError, Equatable, Sendable {
        case missing(String)
        case invalid(String)

        public var errorDescription: String? {
            switch self {
            case .missing(let key):
                return "Missing required configuration: \(key)"
            case .invalid(let key):
                return "Invalid required configuration: \(key)"
            }
        }
    }

    public let supabaseURL: URL
    public let supabasePublishableKey: String

    public init(values: [String: String]) throws {
        guard let rawURL = values["SUPABASE_URL"], !rawURL.isEmpty else {
            throw ConfigurationError.missing("SUPABASE_URL")
        }
        guard
            let url = URL(string: rawURL),
            url.scheme == "https",
            url.host?.isEmpty == false
        else {
            throw ConfigurationError.invalid("SUPABASE_URL")
        }
        guard
            let publishableKey = values["SUPABASE_PUBLISHABLE_KEY"],
            !publishableKey.isEmpty,
            publishableKey != "replace-me",
            !publishableKey.contains("$("),
            !Self.isServerKey(publishableKey)
        else {
            throw ConfigurationError.invalid("SUPABASE_PUBLISHABLE_KEY")
        }

        supabaseURL = url
        supabasePublishableKey = publishableKey
    }

    private static func isServerKey(_ key: String) -> Bool {
        if key.lowercased().hasPrefix("sb_secret_") {
            return true
        }

        let segments = key.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else { return false }

        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)

        guard
            let data = Data(base64Encoded: payload),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let role = object["role"] as? String
        else {
            return false
        }
        return role == "service_role"
    }
}
