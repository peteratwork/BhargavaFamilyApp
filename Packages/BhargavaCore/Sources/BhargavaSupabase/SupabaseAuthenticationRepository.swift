import BhargavaCore
import Foundation
import Supabase

struct RemoteAuthenticatedUser: Equatable, Sendable {
    let userID: UUID
    let email: String
}

struct RemoteAccountAccess: Equatable, Sendable {
    let status: String
    let role: String
    let personID: UUID?
}

struct OTPRequest: Equatable, Sendable {
    let email: String
    let redirectTo: URL
    let shouldCreateUser: Bool
}

protocol SupabaseAuthService: Sendable {
    func restoreUser() async throws -> RemoteAuthenticatedUser?
    func requestEmailOTP(
        email: String,
        redirectTo: URL,
        shouldCreateUser: Bool
    ) async throws
    func user(from callbackURL: URL) async throws -> RemoteAuthenticatedUser
    func fetchAccountAccess() async throws -> RemoteAccountAccess
    func signOut() async throws
}

public actor SupabaseAuthenticationRepository: AuthenticationRepository {
    public enum MappingError: Error, Equatable, Sendable {
        case invalidStatus(String)
        case invalidRole(String)
    }

    private let service: any SupabaseAuthService
    private let callbackURL: URL

    public init(configuration: AppConfiguration, callbackURL: URL) {
        service = LiveSupabaseAuthService(
            supabaseURL: configuration.supabaseURL,
            publishableKey: configuration.supabasePublishableKey
        )
        self.callbackURL = callbackURL
    }

    init(service: any SupabaseAuthService, callbackURL: URL) {
        self.service = service
        self.callbackURL = callbackURL
    }

    public func restoreSession() async throws -> AuthenticatedUser? {
        try await service.restoreUser().map(Self.mapUser)
    }

    public func requestEmailOTP(_ email: String) async throws {
        try await service.requestEmailOTP(
            email: email,
            redirectTo: callbackURL,
            shouldCreateUser: false
        )
    }

    public func handleCallback(_ url: URL) async throws -> AuthenticatedUser {
        Self.mapUser(try await service.user(from: url))
    }

    public func fetchAccountAccess() async throws -> AccountAccess {
        let remote = try await service.fetchAccountAccess()

        guard let status = AccountStatus(rawValue: remote.status) else {
            throw MappingError.invalidStatus(remote.status)
        }
        guard let role = AccountRole(rawValue: remote.role) else {
            throw MappingError.invalidRole(remote.role)
        }

        return AccountAccess(status: status, role: role, personID: remote.personID)
    }

    public func signOut() async throws {
        try await service.signOut()
    }

    private static func mapUser(_ user: RemoteAuthenticatedUser) -> AuthenticatedUser {
        AuthenticatedUser(userID: user.userID, email: user.email)
    }
}

private final class LiveSupabaseAuthService: SupabaseAuthService, @unchecked Sendable {
    enum ServiceError: Error {
        case accountNotFound
        case userEmailMissing
    }

    private struct AccountRow: Decodable {
        let status: String
        let role: String
        let personID: UUID?

        enum CodingKeys: String, CodingKey {
            case status
            case role
            case personID = "person_id"
        }
    }

    private let client: SupabaseClient

    init(supabaseURL: URL, publishableKey: String) {
        client = SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: publishableKey
        )
    }

    func restoreUser() async throws -> RemoteAuthenticatedUser? {
        do {
            return try mapUser((try await client.auth.session).user)
        } catch AuthError.sessionMissing {
            return nil
        }
    }

    func requestEmailOTP(
        email: String,
        redirectTo: URL,
        shouldCreateUser: Bool
    ) async throws {
        try await client.auth.signInWithOTP(
            email: email,
            redirectTo: redirectTo,
            shouldCreateUser: shouldCreateUser
        )
    }

    func user(from callbackURL: URL) async throws -> RemoteAuthenticatedUser {
        try mapUser((try await client.auth.session(from: callbackURL)).user)
    }

    func fetchAccountAccess() async throws -> RemoteAccountAccess {
        let userID = try await client.auth.session.user.id
        let response: PostgrestResponse<[AccountRow]> = try await client
            .from("accounts")
            .select("status,role,person_id")
            .eq("id", value: userID.uuidString)
            .limit(1)
            .execute()

        guard let row = response.value.first else {
            throw ServiceError.accountNotFound
        }

        return RemoteAccountAccess(
            status: row.status,
            role: row.role,
            personID: row.personID
        )
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    private func mapUser(_ user: User) throws -> RemoteAuthenticatedUser {
        guard let email = user.email else {
            throw ServiceError.userEmailMissing
        }
        return RemoteAuthenticatedUser(userID: user.id, email: email)
    }
}
