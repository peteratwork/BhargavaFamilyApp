import BhargavaCore
import SwiftUI

struct CheckEmailView: View {
    let session: AppSession
    let email: String
    @State private var resendSeconds = 30

    var body: some View {
        ContentUnavailableView {
            Label("Check your email", systemImage: "envelope.badge")
        } description: {
            Text("Open the secure sign-in link sent to \(email). The message is the same whether or not an invitation is active.")
        } actions: {
            VStack(spacing: 12) {
                Button(resendSeconds > 0 ? "Resend in \(resendSeconds)s" : "Resend link") {
                    resendSeconds = 30
                    Task { await session.requestOTP(email: email) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(resendSeconds > 0)
                .accessibilityLabel(resendSeconds > 0 ? "Resend available in \(resendSeconds) seconds" : "Resend secure sign-in link")

                Button("Use a different email") {
                    Task { await session.signOut() }
                }
                .accessibilityLabel("Change invitation email")
            }
        }
        .task(id: resendSeconds == 30) {
            while resendSeconds > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                resendSeconds -= 1
            }
        }
    }
}
