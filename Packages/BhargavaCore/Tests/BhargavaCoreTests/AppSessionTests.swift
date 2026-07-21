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

    func testOTPRequestFailureDoesNotRevealWhetherInvitationExists() async {
        let repository = StubAuthenticationRepository(
            restoredUser: nil,
            requestError: StubError.requestFailed
        )
        let session = AppSession(repository: repository, initialState: .signedOut)

        await session.requestOTP(email: "unknown@example.com")

        XCTAssertEqual(repository.requestedEmails, ["unknown@example.com"])
        XCTAssertEqual(session.state, .awaitingEmail(email: "unknown@example.com"))
    }

    func testValidEmailOTPVerifiesAndRoutesToPendingClaim() async {
        let repository = StubAuthenticationRepository(restoredUser: nil)
        let session = AppSession(repository: repository, initialState: .awaitingEmail(email: "member@example.com"))

        await session.verifyOTP(email: "member@example.com", code: "123456")

        XCTAssertEqual(repository.verifiedOTPs, ["member@example.com:123456"])
        XCTAssertFalse(session.otpVerificationFailed)
        XCTAssertEqual(session.state, .pendingClaim)
    }

    func testMalformedEmailOTPStaysOnEntryWithoutCallingRepository() async {
        let repository = StubAuthenticationRepository(restoredUser: nil)
        let session = AppSession(repository: repository, initialState: .awaitingEmail(email: "member@example.com"))

        await session.verifyOTP(email: "member@example.com", code: "12ab")

        XCTAssertEqual(repository.verifiedOTPs, [])
        XCTAssertTrue(session.otpVerificationFailed)
        XCTAssertEqual(session.state, .awaitingEmail(email: "member@example.com"))
    }

    func testRejectedEmailOTPStaysOnEntryForRetry() async {
        let repository = StubAuthenticationRepository(
            restoredUser: nil,
            verificationError: StubError.requestFailed
        )
        let session = AppSession(repository: repository, initialState: .awaitingEmail(email: "member@example.com"))

        await session.verifyOTP(email: "member@example.com", code: "123456")

        XCTAssertTrue(session.otpVerificationFailed)
        XCTAssertEqual(session.state, .awaitingEmail(email: "member@example.com"))
    }

    func testSuccessfulOTPWithAccountFailureOffersAccountRefreshRetry() async {
        let repository = StubAuthenticationRepository(
            restoredUser: nil,
            accountError: StubError.requestFailed
        )
        let session = AppSession(repository: repository, initialState: .awaitingEmail(email: "member@example.com"))

        await session.verifyOTP(email: "member@example.com", code: "123456")

        XCTAssertEqual(repository.verifiedOTPs, ["member@example.com:123456"])
        XCTAssertFalse(session.otpVerificationFailed)
        XCTAssertEqual(session.state, .accountRefreshFailed)
    }

    func testSignOutWaitsForInFlightOTPVerificationThenClearsItsSession() async {
        let repository = DelayedVerificationRepository()
        let session = AppSession(repository: repository, initialState: .awaitingEmail(email: "member@example.com"))

        let verification = Task {
            await session.verifyOTP(email: "member@example.com", code: "123456")
        }
        await repository.waitForVerification()
        let signOut = Task { await session.signOut() }
        await Task.yield()
        await repository.completeVerification()
        await verification.value
        await signOut.value

        let hasSession = await repository.hasSession
        let events = await repository.events
        XCTAssertFalse(hasSession)
        XCTAssertEqual(events, ["verify-start", "verify-finish", "sign-out"])
        XCTAssertEqual(session.state, .signedOut)
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

    func verifyEmailOTP(email: String, code: String) async throws -> AuthenticatedUser {
        .init(userID: UUID(), email: email)
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

private actor DelayedVerificationRepository: AuthenticationRepository {
    private var verificationContinuation: CheckedContinuation<Void, Never>?
    private(set) var hasSession = false
    private(set) var events: [String] = []

    func restoreSession() async throws -> AuthenticatedUser? { nil }
    func requestEmailOTP(_ email: String) async throws {}

    func verifyEmailOTP(email: String, code: String) async throws -> AuthenticatedUser {
        events.append("verify-start")
        await withCheckedContinuation { continuation in
            verificationContinuation = continuation
        }
        hasSession = true
        events.append("verify-finish")
        return .init(userID: UUID(), email: email)
    }

    func handleCallback(_ url: URL) async throws -> AuthenticatedUser {
        .init(userID: UUID(), email: "member@example.com")
    }

    func fetchAccountAccess() async throws -> AccountAccess {
        .init(status: .pending, role: .member, personID: nil)
    }

    func signOut() async throws {
        hasSession = false
        events.append("sign-out")
    }

    func waitForVerification() async {
        while verificationContinuation == nil {
            await Task.yield()
        }
    }

    func completeVerification() {
        verificationContinuation?.resume()
        verificationContinuation = nil
    }
}

private final class StubAuthenticationRepository: AuthenticationRepository, @unchecked Sendable {
    let restoredUser: AuthenticatedUser?
    var accountAccess: AccountAccess
    let restoreError: Error?
    let requestError: Error?
    let verificationError: Error?
    let accountError: Error?
    var requestedEmails: [String] = []
    var verifiedOTPs: [String] = []
    var didSignOut = false

    init(
        restoredUser: AuthenticatedUser?,
        accountAccess: AccountAccess = .init(status: .pending, role: .member, personID: nil),
        restoreError: Error? = nil,
        requestError: Error? = nil,
        verificationError: Error? = nil,
        accountError: Error? = nil
    ) {
        self.restoredUser = restoredUser
        self.accountAccess = accountAccess
        self.restoreError = restoreError
        self.requestError = requestError
        self.verificationError = verificationError
        self.accountError = accountError
    }

    func restoreSession() async throws -> AuthenticatedUser? {
        if let restoreError {
            throw restoreError
        }
        return restoredUser
    }

    func requestEmailOTP(_ email: String) async throws {
        requestedEmails.append(email)
        if let requestError {
            throw requestError
        }
    }

    func verifyEmailOTP(email: String, code: String) async throws -> AuthenticatedUser {
        verifiedOTPs.append("\(email):\(code)")
        if let verificationError {
            throw verificationError
        }
        return .init(userID: UUID(), email: email)
    }

    func handleCallback(_ url: URL) async throws -> AuthenticatedUser {
        restoredUser ?? .init(userID: UUID(), email: "invitee@example.com")
    }

    func fetchAccountAccess() async throws -> AccountAccess {
        if let accountError {
            throw accountError
        }
        accountAccess
    }

    func signOut() async throws {
        didSignOut = true
    }
}

private enum StubError: Error {
    case requestFailed
}
