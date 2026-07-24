import BhargavaCore
import SwiftUI

struct CheckEmailView: View {
    let session: AppSession
    let email: String
    @State private var code = ""
    @State private var resendSeconds = 60

    var body: some View {
        ContentUnavailableView {
            Label("Enter your email code", systemImage: "number.square")
        } description: {
            Text("If this email has an active invitation, a six-digit code will arrive at \(email). Check spam or junk mail before requesting another code.")
        } actions: {
            VStack(spacing: 12) {
                TextField("6-digit code", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .multilineTextAlignment(.center)
                    .font(.title2.monospacedDigit())
                    .frame(maxWidth: 220)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: code) { _, newValue in
                        code = String(newValue.filter { $0.isASCII && $0.isNumber }.prefix(6))
                    }

                if session.otpVerificationFailed {
                    Text("That code is invalid or expired. Request a new code and try again.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button(session.isVerifyingOTP ? "Verifying…" : "Verify code") {
                    Task { await session.verifyOTP(email: email, code: code) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(code.count != 6 || session.isVerifyingOTP)

                Button(resendSeconds > 0 ? "Resend in \(resendSeconds)s" : "Resend code") {
                    resendSeconds = 60
                    code = ""
                    Task { await session.requestOTP(email: email) }
                }
                .disabled(resendSeconds > 0)
                .accessibilityLabel(resendSeconds > 0 ? "Resend available in \(resendSeconds) seconds" : "Resend email code")

                Button("Use a different email") {
                    Task { await session.signOut() }
                }
                .accessibilityLabel("Change invitation email")
            }
        }
        .task(id: resendSeconds == 60) {
            while resendSeconds > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                resendSeconds -= 1
            }
        }
    }
}
