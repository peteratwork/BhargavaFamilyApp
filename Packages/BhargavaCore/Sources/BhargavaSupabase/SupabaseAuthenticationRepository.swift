import BhargavaCore
import Foundation
import Supabase

enum SupabaseClientConfiguration {
    static let authenticationFlowType: AuthFlowType = .implicit

    static var options: SupabaseClientOptions {
        SupabaseClientOptions(
            auth: .init(flowType: authenticationFlowType)
        )
    }
}

enum SupabaseDatabaseSchema {
    static let accountAccessRPC = "refresh_own_account_state"
}

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
        do {
            guard let remoteUser = try await service.restoreUser() else { return nil }
            return Self.mapUser(remoteUser)
        } catch {
            throw Self.mapServiceError(error)
        }
    }

    public func requestEmailOTP(_ email: String) async throws {
        do {
            try await service.requestEmailOTP(
                email: email,
                redirectTo: callbackURL,
                shouldCreateUser: false
            )
        } catch {
            throw Self.mapServiceError(error)
        }
    }

    public func handleCallback(_ url: URL) async throws -> AuthenticatedUser {
        do {
            return Self.mapUser(try await service.user(from: url))
        } catch {
            throw Self.mapServiceError(error)
        }
    }

    public func fetchAccountAccess() async throws -> AccountAccess {
        let remote: RemoteAccountAccess
        do {
            remote = try await service.fetchAccountAccess()
        } catch {
            throw Self.mapServiceError(error)
        }

        guard let status = AccountStatus(rawValue: remote.status) else {
            throw MappingError.invalidStatus(remote.status)
        }
        guard let role = AccountRole(rawValue: remote.role) else {
            throw MappingError.invalidRole(remote.role)
        }

        return AccountAccess(status: status, role: role, personID: remote.personID)
    }

    public func signOut() async throws {
        do {
            try await service.signOut()
        } catch {
            throw Self.mapServiceError(error)
        }
    }

    private static func mapUser(_ user: RemoteAuthenticatedUser) -> AuthenticatedUser {
        AuthenticatedUser(userID: user.userID, email: user.email)
    }

    private static func mapServiceError(_ error: Error) -> Error {
        if case AuthError.sessionMissing = error {
            return AuthenticationRepositoryError.sessionExpired
        }

        if case let AuthError.api(_, errorCode, _, response) = error,
           response.statusCode == 401 || [
               .sessionNotFound,
               .sessionExpired,
               .refreshTokenNotFound,
               .refreshTokenAlreadyUsed
           ].contains(errorCode) {
            return AuthenticationRepositoryError.sessionExpired
        }

        if let error = error as? HTTPError, error.response.statusCode == 401 {
            return AuthenticationRepositoryError.sessionExpired
        }

        if let error = error as? PostgrestError,
           let code = error.code,
           ["PGRST301", "PGRST302"].contains(code) {
            return AuthenticationRepositoryError.sessionExpired
        }

        return error
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
            supabaseKey: publishableKey,
            options: SupabaseClientConfiguration.options
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
        let response: PostgrestResponse<[AccountRow]> = try await client
            .rpc(SupabaseDatabaseSchema.accountAccessRPC)
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
