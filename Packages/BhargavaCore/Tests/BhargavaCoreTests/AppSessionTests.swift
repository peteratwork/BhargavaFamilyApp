import Foundation
import XCTest
@testable import BhargavaCore

@MainActor
final class AppSessionTests: XCTestCase {
    func testMissingRestoredSessionRoutesToSignedOut() async {
        let repository = StubAuthenticationRepository(restoredUser: nil)
        let session = AppSession(repository: repository)

        await session.restore()

        XCTAssertEqual(session.state, .signedOut)
    }

    func testPendingAccountRoutesToPendingClaim() async {
        let repository = StubAuthenticationRepository(
            restoredUser: .init(userID: UUID(), email: "invitee@example.com"),
            accountAccess: .init(status: .pending, role: .member, personID: nil)
        )
        let session = AppSession(repository: repository)

        await session.restore()

        XCTAssertEqual(session.state, .pendingClaim)
    }

    func testApprovedAccountRoutesToApprovedContent() async {
        let personID = UUID()
        let access = AccountAccess(status: .approved, role: .member, personID: personID)
        let repository = StubAuthenticationRepository(
            restoredUser: .init(userID: UUID(), email: "member@example.com"),
            accountAccess: access
        )
        let session = AppSession(repository: repository)

        await session.restore()

        XCTAssertEqual(session.state, .approved(access))
    }

    func testSuspendedAccountRoutesToBlockedContent() async {
        let repository = StubAuthenticationRepository(
            restoredUser: .init(userID: UUID(), email: "member@example.com"),
            accountAccess: .init(status: .suspended, role: .member, personID: nil)
        )
        let session = AppSession(repository: repository)

        await session.restore()

        XCTAssertEqual(session.state, .blocked)
    }

    func testRequestOTPNormalizesEmailAndWaitsForCallback() async {
        let repository = StubAuthenticationRepository(restoredUser: nil)
        let session = AppSession(repository: repository)

        await session.requestOTP(email: "  Member@Example.COM ")

        XCTAssertEqual(repository.requestedEmails, ["member@example.com"])
        XCTAssertEqual(session.state, .awaitingEmail(email: "member@example.com"))
    }

    func testSignOutClearsRepositorySessionBeforePublishingSignedOut() async {
        let repository = StubAuthenticationRepository(
            restoredUser: .init(userID: UUID(), email: "member@example.com"),
            accountAccess: .init(status: .approved, role: .member, personID: UUID())
        )
        let session = AppSession(repository: repository)
        await session.restore()

        await session.signOut()

        XCTAssertTrue(repository.didSignOut)
        XCTAssertEqual(session.state, .signedOut)
    }
}

private final class StubAuthenticationRepository: AuthenticationRepository, @unchecked Sendable {
    let restoredUser: AuthenticatedUser?
    let accountAccess: AccountAccess
    var requestedEmails: [String] = []
    var didSignOut = false

    init(
        restoredUser: AuthenticatedUser?,
        accountAccess: AccountAccess = .init(status: .pending, role: .member, personID: nil)
    ) {
        self.restoredUser = restoredUser
        self.accountAccess = accountAccess
    }

    func restoreSession() async throws -> AuthenticatedUser? {
        restoredUser
    }

    func requestEmailOTP(_ email: String) async throws {
        requestedEmails.append(email)
    }

    func handleCallback(_ url: URL) async throws -> AuthenticatedUser {
        restoredUser ?? .init(userID: UUID(), email: "invitee@example.com")
    }

    func fetchAccountAccess() async throws -> AccountAccess {
        accountAccess
    }

    func signOut() async throws {
        didSignOut = true
    }
}
