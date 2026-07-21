import BhargavaCore
import Foundation
import Supabase
import XCTest
@testable import BhargavaSupabase

final class SupabaseAuthenticationRepositoryTests: XCTestCase {
    func testServerOriginatedInviteLinksUseImplicitCallbackFlow() {
        switch SupabaseClientConfiguration.authenticationFlowType {
        case .implicit:
            break
        case .pkce:
            XCTFail("PKCE requires a verifier from a flow initiated on this device")
        }
    }

    func testAccountLookupUsesMigratedPrimaryKeyColumn() {
        XCTAssertEqual(SupabaseDatabaseSchema.accountUserIDColumn, "user_id")
    }

    func testOTPRequestDisablesAccountCreationAndUsesConfiguredCallback() async throws {
        let callbackURL = try XCTUnwrap(URL(string: "bhargavafamily://auth-callback"))
        let service = StubSupabaseAuthService()
        let repository = SupabaseAuthenticationRepository(
            service: service,
            callbackURL: callbackURL
        )

        try await repository.requestEmailOTP("invitee@example.com")

        let request = await service.lastOTPRequest
        XCTAssertEqual(request?.email, "invitee@example.com")
        XCTAssertEqual(request?.redirectTo, callbackURL)
        XCTAssertEqual(request?.shouldCreateUser, false)
    }

    func testRestoreMapsRemoteUser() async throws {
        let userID = UUID()
        let service = StubSupabaseAuthService(
            restoredUser: .init(userID: userID, email: "member@example.com")
        )
        let repository = SupabaseAuthenticationRepository(
            service: service,
            callbackURL: URL(string: "bhargavafamily://auth-callback")!
        )

        let user = try await repository.restoreSession()

        XCTAssertEqual(
            user,
            .init(userID: userID, email: "member@example.com")
        )
    }

    func testAccountAccessMapsDatabaseValues() async throws {
        let personID = UUID()
        let service = StubSupabaseAuthService(
            accountAccess: .init(
                status: "approved",
                role: "trusted_elder",
                personID: personID
            )
        )
        let repository = SupabaseAuthenticationRepository(
            service: service,
            callbackURL: URL(string: "bhargavafamily://auth-callback")!
        )

        let access = try await repository.fetchAccountAccess()

        XCTAssertEqual(
            access,
            .init(status: .approved, role: .trustedElder, personID: personID)
        )
    }

    func testUnknownAccountValuesFailClosed() async {
        let service = StubSupabaseAuthService(
            accountAccess: .init(status: "approved", role: "super_admin", personID: nil)
        )
        let repository = SupabaseAuthenticationRepository(
            service: service,
            callbackURL: URL(string: "bhargavafamily://auth-callback")!
        )

        do {
            _ = try await repository.fetchAccountAccess()
            XCTFail("Expected an invalid account access error")
        } catch let error as SupabaseAuthenticationRepository.MappingError {
            XCTAssertEqual(error, .invalidRole("super_admin"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private actor StubSupabaseAuthService: SupabaseAuthService {
    private let restoredUser: RemoteAuthenticatedUser?
    private let accountAccess: RemoteAccountAccess
    private(set) var lastOTPRequest: OTPRequest?

    init(
        restoredUser: RemoteAuthenticatedUser? = nil,
        accountAccess: RemoteAccountAccess = .init(
            status: "pending",
            role: "member",
            personID: nil
        )
    ) {
        self.restoredUser = restoredUser
        self.accountAccess = accountAccess
    }

    func restoreUser() async throws -> RemoteAuthenticatedUser? {
        restoredUser
    }

    func requestEmailOTP(
        email: String,
        redirectTo: URL,
        shouldCreateUser: Bool
    ) async throws {
        lastOTPRequest = .init(
            email: email,
            redirectTo: redirectTo,
            shouldCreateUser: shouldCreateUser
        )
    }

    func user(from callbackURL: URL) async throws -> RemoteAuthenticatedUser {
        restoredUser ?? .init(userID: UUID(), email: "member@example.com")
    }

    func fetchAccountAccess() async throws -> RemoteAccountAccess {
        accountAccess
    }

    func signOut() async throws {}
}
