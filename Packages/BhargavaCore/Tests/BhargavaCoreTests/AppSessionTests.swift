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

    func testPendingAccountRefreshRoutesToApprovedContentAfterReview() async {
        let repository = StubAuthenticationRepository(
            restoredUser: .init(userID: UUID(), email: "member@example.com"),
            accountAccess: .init(status: .pending, role: .member, personID: nil)
        )
        let session = AppSession(repository: repository)
        await session.restore()
        let approvedAccess = AccountAccess(
            status: .approved,
            role: .member,
            personID: UUID()
        )
        repository.accountAccess = approvedAccess

        await session.refreshAccount()

        XCTAssertEqual(session.state, .approved(approvedAccess))
    }

    func testExpiredRestoredSessionSignsOutAndRoutesToSignedOut() async {
        let repository = StubAuthenticationRepository(
            restoredUser: .init(userID: UUID(), email: "member@example.com"),
            restoreError: AuthenticationRepositoryError.sessionExpired
        )
        let session = AppSession(repository: repository)

        await session.restore()

        XCTAssertTrue(repository.didSignOut)
        XCTAssertEqual(session.state, .signedOut)
    }

    func testRequestOTPNormalizesEmailAndWaitsForCallback() async {
        let repository = StubAuthenticationRepository(restoredUser: nil)
        let session = AppSession(repository: repository)

        await session.requestOTP(email: "  Member@Example.COM ")

        XCTAssertEqual(repository.requestedEmails, ["member@example.com"])
        XCTAssertEqual(session.state, .awaitingEmail(email: "member@example.com"))
    }

    func testInvalidEmailDoesNotReachRepository() async {
        let repository = StubAuthenticationRepository(restoredUser: nil)
        let session = AppSession(repository: repository, initialState: .signedOut)

        await session.requestOTP(email: "not-an-email")

        XCTAssertEqual(repository.requestedEmails, [])
        XCTAssertEqual(session.state, .failed(.invalidEmail))
    }

    func testWhitespaceOnlyEmailDoesNotReachRepository() async {
        let repository = StubAuthenticationRepository(restoredUser: nil)
        let session = AppSession(repository: repository, initialState: .signedOut)

        await session.requestOTP(email: "   \n")

        XCTAssertEqual(repository.requestedEmails, [])
        XCTAssertEqual(session.state, .failed(.invalidEmail))
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

    func testCompletedOTPRequestDoesNotOverwriteNewerSignOut() async {
        let repository = DelayedAuthenticationRepository()
        let session = AppSession(repository: repository)

        let request = Task {
            await session.requestOTP(email: "member@example.com")
        }
        await repository.waitForOTPRequest()

        await session.signOut()
        await repository.completeOTPRequest()
        await request.value

        XCTAssertEqual(session.state, .signedOut)
    }
}

private actor DelayedAuthenticationRepository: AuthenticationRepository {
    private var otpContinuation: CheckedContinuation<Void, Error>?

    func restoreSession() async throws -> AuthenticatedUser? {
        nil
    }

    func requestEmailOTP(_ email: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            otpContinuation = continuation
        }
    }

    func handleCallback(_ url: URL) async throws -> AuthenticatedUser {
        .init(userID: UUID(), email: "member@example.com")
    }

    func fetchAccountAccess() async throws -> AccountAccess {
        .init(status: .approved, role: .member, personID: UUID())
    }

    func signOut() async throws {}

    func waitForOTPRequest() async {
        while otpContinuation == nil {
            await Task.yield()
        }
    }

    func completeOTPRequest() {
        otpContinuation?.resume()
        otpContinuation = nil
    }
}

private final class StubAuthenticationRepository: AuthenticationRepository, @unchecked Sendable {
    let restoredUser: AuthenticatedUser?
    var accountAccess: AccountAccess
    let restoreError: Error?
    var requestedEmails: [String] = []
    var didSignOut = false

    init(
        restoredUser: AuthenticatedUser?,
        accountAccess: AccountAccess = .init(status: .pending, role: .member, personID: nil),
        restoreError: Error? = nil
    ) {
        self.restoredUser = restoredUser
        self.accountAccess = accountAccess
        self.restoreError = restoreError
    }

    func restoreSession() async throws -> AuthenticatedUser? {
        if let restoreError {
            throw restoreError
        }
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
