import Foundation
import Observation

@MainActor
@Observable
public final class AppSession {
    public enum State: Equatable, Sendable {
        case restoring
        case signedOut
        case requestingOTP(email: String)
        case awaitingEmail(email: String)
        case pendingClaim
        case approved(AccountAccess)
        case blocked
        case failed(SessionError)
    }

    public private(set) var state: State

    private let repository: any AuthenticationRepository

    public init(
        repository: any AuthenticationRepository,
        initialState: State = .restoring
    ) {
        self.repository = repository
        state = initialState
    }

    public func restore() async {
        state = .restoring

        do {
            guard try await repository.restoreSession() != nil else {
                state = .signedOut
                return
            }

            try await routeUsingAccountAccess()
        } catch {
            state = .failed(.serviceUnavailable)
        }
    }

    public func requestOTP(email rawEmail: String) async {
        let email = rawEmail
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
        state = .requestingOTP(email: email)

        do {
            try await repository.requestEmailOTP(email)
            state = .awaitingEmail(email: email)
        } catch {
            state = .failed(.requestFailed)
        }
    }

    public func handleCallback(_ url: URL) async {
        state = .restoring

        do {
            _ = try await repository.handleCallback(url)
            try await routeUsingAccountAccess()
        } catch {
            state = .failed(.authenticationFailed)
        }
    }

    public func signOut() async {
        do {
            try await repository.signOut()
            state = .signedOut
        } catch {
            state = .failed(.serviceUnavailable)
        }
    }

    private func routeUsingAccountAccess() async throws {
        let access = try await repository.fetchAccountAccess()

        switch access.status {
        case .pending:
            state = .pendingClaim
        case .approved:
            state = .approved(access)
        case .suspended, .closed:
            state = .blocked
        }
    }
}
