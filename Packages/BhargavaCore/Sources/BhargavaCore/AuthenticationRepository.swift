import Foundation

public protocol AuthenticationRepository: Sendable {
    func restoreSession() async throws -> AuthenticatedUser?
    func requestEmailOTP(_ email: String) async throws
    func handleCallback(_ url: URL) async throws -> AuthenticatedUser
    func fetchAccountAccess() async throws -> AccountAccess
    func signOut() async throws
}
