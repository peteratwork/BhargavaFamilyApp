import BhargavaCore
import SwiftUI

struct SignInView: View {
    let session: AppSession
    let error: SessionError?
    @State private var email: String

    init(
        session: AppSession,
        initialEmail: String = "",
        error: SessionError? = nil
    ) {
        self.session = session
        self.error = error
        _email = State(initialValue: initialEmail)
    }

    private var isRequesting: Bool {
        if case .requestingOTP = session.state { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Bhargava Family is private and invitation-only. Use the email address from your invitation.")
                        .foregroundStyle(.secondary)
                }

                Section("Email") {
                    TextField("you@example.com", text: $email)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Invitation email")

                    Button {
                        Task { await session.requestOTP(email: email) }
                    } label: {
                        if isRequesting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Email me a secure sign-in link")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!EmailAddress.isValid(email) || isRequesting)
                    .accessibilityLabel("Send secure sign-in link")
                }

                if let error {
                    Section {
                        Text(message(for: error))
                            .foregroundStyle(.red)
                            .accessibilityLabel("Sign-in error. \(message(for: error))")
                    }
                }
            }
            .navigationTitle("Welcome")
        }
    }

    private func message(for error: SessionError) -> String {
        switch error {
        case .invalidEmail:
            return "Enter a valid email address."
        case .authenticationFailed:
            return "That sign-in link could not be verified. Request a new link and try again."
        case .requestFailed, .serviceUnavailable:
            return "We could not complete sign-in. Check your connection and try again."
        }
    }
}
