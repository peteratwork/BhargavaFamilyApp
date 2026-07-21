import Foundation

public enum EmailAddress {
    public static func normalized(_ rawValue: String) -> String {
        rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
    }

    public static func isValid(_ rawValue: String) -> Bool {
        let value = normalized(rawValue)
        guard value.count <= 254, !value.contains(where: { $0.isWhitespace }) else {
            return false
        }

        let components = value.split(separator: "@", omittingEmptySubsequences: false)
        guard
            components.count == 2,
            !components[0].isEmpty,
            components[0].count <= 64
        else {
            return false
        }

        let domainLabels = components[1].split(separator: ".", omittingEmptySubsequences: false)
        guard domainLabels.count >= 2 else { return false }

        return domainLabels.allSatisfy { label in
            guard
                !label.isEmpty,
                label.count <= 63,
                label.first != "-",
                label.last != "-"
            else {
                return false
            }
            return label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
    }
}
