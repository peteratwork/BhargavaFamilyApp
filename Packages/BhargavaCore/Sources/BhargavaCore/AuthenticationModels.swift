import Foundation

public struct AuthenticatedUser: Equatable, Sendable {
    public let userID: UUID
    public let email: String

    public init(userID: UUID, email: String) {
        self.userID = userID
        self.email = email
    }
}

public enum AccountStatus: String, Codable, Sendable {
    case pending
    case approved
    case suspended
    case closed
}

public enum AccountRole: String, Codable, Sendable {
    case member
    case trustedElder = "trusted_elder"
    case admin
}

public struct AccountAccess: Equatable, Codable, Sendable {
    public let status: AccountStatus
    public let role: AccountRole
    public let personID: UUID?

    public init(status: AccountStatus, role: AccountRole, personID: UUID?) {
        self.status = status
        self.role = role
        self.personID = personID
    }
}

public enum SessionError: String, Equatable, Sendable {
    case authenticationFailed
    case invalidEmail
    case requestFailed
    case serviceUnavailable
}
