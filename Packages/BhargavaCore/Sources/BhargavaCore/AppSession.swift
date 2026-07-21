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
        case accountRefreshFailed
        case failed(SessionError)
    }

    public private(set) var state: State
    public private(set) var isVerifyingOTP = false
    public private(set) var otpVerificationFailed = false

    private let repository: any AuthenticationRepository
    private let authenticationMutations = AuthenticationMutationQueue()
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
        let restoredUser: AuthenticatedUser?
        let repository = self.repository

        do {
            restoredUser = try await authenticationMutations.run {
                try await repository.restoreSession()
            }
        } catch AuthenticationRepositoryError.sessionExpired {
            await expireSession(operation: operation)
            return
        } catch {
            guard isCurrent(operation) else { return }
            state = .failed(.serviceUnavailable)
            return
        }

        guard isCurrent(operation) else { return }
        guard restoredUser != nil else {
            state = .signedOut
            return
        }

        do {
            let destination = try await accountDestination()
            guard isCurrent(operation) else { return }
            state = destination
        } catch AuthenticationRepositoryError.sessionExpired {
            await expireSession(operation: operation)
        } catch {
            guard isCurrent(operation) else { return }
            state = .accountRefreshFailed
        }
    }

    public func refreshAccount() async {
        let operation = beginOperation(state: .restoring)

        do {
            let destination = try await accountDestination()
            guard isCurrent(operation) else { return }
            state = destination
        } catch AuthenticationRepositoryError.sessionExpired {
            await expireSession(operation: operation)
        } catch {
            guard isCurrent(operation) else { return }
            state = .accountRefreshFailed
        }
    }

    public func requestOTP(email rawEmail: String) async {
        let email = EmailAddress.normalized(rawEmail)
        guard EmailAddress.isValid(email) else {
            _ = beginOperation(state: .failed(.invalidEmail))
            return
        }
        let operation = beginOperation(state: .requestingOTP(email: email))
        otpVerificationFailed = false

        do {
            try await repository.requestEmailOTP(email)
            guard isCurrent(operation) else { return }
            state = .awaitingEmail(email: email)
        } catch {
            guard isCurrent(operation) else { return }
            // Keep the public result identical for invited and unknown addresses.
            // This prevents account or invitation enumeration from the UI.
            state = .awaitingEmail(email: email)
        }
    }

    public func verifyOTP(email rawEmail: String, code rawCode: String) async {
        let email = EmailAddress.normalized(rawEmail)
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.count == 6, code.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            otpVerificationFailed = true
            return
        }

        let operation = beginOperation(state: .awaitingEmail(email: email))
        isVerifyingOTP = true
        otpVerificationFailed = false
        defer {
            if isCurrent(operation) {
                isVerifyingOTP = false
            }
        }
        let repository = self.repository

        do {
            _ = try await authenticationMutations.run {
                try await repository.verifyEmailOTP(email: email, code: code)
            }
        } catch AuthenticationRepositoryError.sessionExpired {
            await expireSession(operation: operation)
            return
        } catch {
            guard isCurrent(operation) else { return }
            otpVerificationFailed = true
            state = .awaitingEmail(email: email)
            return
        }

        guard isCurrent(operation) else { return }
        do {
            let destination = try await accountDestination()
            guard isCurrent(operation) else { return }
            state = destination
        } catch AuthenticationRepositoryError.sessionExpired {
            await expireSession(operation: operation)
        } catch {
            guard isCurrent(operation) else { return }
            state = .accountRefreshFailed
        }
    }

    public func handleCallback(_ url: URL) async {
        let operation = beginOperation(state: .restoring)
        let repository = self.repository

        do {
            _ = try await authenticationMutations.run {
                try await repository.handleCallback(url)
            }
            guard isCurrent(operation) else { return }

        } catch {
            guard isCurrent(operation) else { return }
            state = .failed(.authenticationFailed)
            return
        }

        do {
            let destination = try await accountDestination()
            guard isCurrent(operation) else { return }
            state = destination
        } catch AuthenticationRepositoryError.sessionExpired {
            await expireSession(operation: operation)
        } catch {
            guard isCurrent(operation) else { return }
            state = .accountRefreshFailed
        }
    }

    public func signOut() async {
        let operation = beginOperation(state: state)
        let repository = self.repository

        do {
            try await authenticationMutations.run {
                try await repository.signOut()
            }
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
        isVerifyingOTP = false
        state = nextState
        return operationGeneration
    }

    private func isCurrent(_ operation: Int) -> Bool {
        operation == operationGeneration
    }

    private func expireSession(operation: Int) async {
        guard isCurrent(operation) else { return }
        let repository = self.repository
        try? await authenticationMutations.run {
            try await repository.signOut()
        }
        guard isCurrent(operation) else { return }
        state = .signedOut
    }
}

private actor AuthenticationMutationQueue {
    private var tail = Task<Void, Never> {}

    func run<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let predecessor = tail
        let task = Task<Value, Error> {
            await predecessor.value
            return try await operation()
        }
        tail = Task {
            _ = try? await task.value
        }
        return try await task.value
    }
}
