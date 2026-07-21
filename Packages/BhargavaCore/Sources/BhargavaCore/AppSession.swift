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
    private var operationGeneration = 0

    public init(
        repository: any AuthenticationRepository,
        initialState: State = .restoring
    ) {
        self.repository = repository
        state = initialState
    }

    public func restore() async {
        let operation = beginOperation(state: .restoring)

        do {
            let restoredUser = try await repository.restoreSession()
            guard isCurrent(operation) else { return }

            guard restoredUser != nil else {
                state = .signedOut
                return
            }

            let destination = try await accountDestination()
            guard isCurrent(operation) else { return }
            state = destination
        } catch {
            guard isCurrent(operation) else { return }
            state = .failed(.serviceUnavailable)
        }
    }

    public func requestOTP(email rawEmail: String) async {
        let email = EmailAddress.normalized(rawEmail)
        guard EmailAddress.isValid(email) else {
            _ = beginOperation(state: .failed(.invalidEmail))
            return
        }
        let operation = beginOperation(state: .requestingOTP(email: email))

        do {
            try await repository.requestEmailOTP(email)
            guard isCurrent(operation) else { return }
            state = .awaitingEmail(email: email)
        } catch {
            guard isCurrent(operation) else { return }
            state = .failed(.requestFailed)
        }
    }

    public func handleCallback(_ url: URL) async {
        let operation = beginOperation(state: .restoring)

        do {
            _ = try await repository.handleCallback(url)
            guard isCurrent(operation) else { return }

            let destination = try await accountDestination()
            guard isCurrent(operation) else { return }
            state = destination
        } catch {
            guard isCurrent(operation) else { return }
            state = .failed(.authenticationFailed)
        }
    }

    public func signOut() async {
        let operation = beginOperation(state: state)

        do {
            try await repository.signOut()
            guard isCurrent(operation) else { return }
            state = .signedOut
        } catch {
            guard isCurrent(operation) else { return }
            state = .failed(.serviceUnavailable)
        }
    }

    private func accountDestination() async throws -> State {
        let access = try await repository.fetchAccountAccess()

        switch access.status {
        case .pending:
            return .pendingClaim
        case .approved:
            return .approved(access)
        case .suspended, .closed:
            return .blocked
        }
    }

    private func beginOperation(state nextState: State) -> Int {
        operationGeneration &+= 1
        state = nextState
        return operationGeneration
    }

    private func isCurrent(_ operation: Int) -> Bool {
        operation == operationGeneration
    }
}
