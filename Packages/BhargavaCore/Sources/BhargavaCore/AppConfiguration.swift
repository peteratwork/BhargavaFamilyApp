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
            publishableKey != "replace-me"
        else {
            throw ConfigurationError.invalid("SUPABASE_PUBLISHABLE_KEY")
        }

        supabaseURL = url
        supabasePublishableKey = publishableKey
    }
}
