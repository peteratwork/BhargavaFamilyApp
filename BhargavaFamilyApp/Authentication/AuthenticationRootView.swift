import BhargavaCore
import SwiftUI

struct AuthenticationRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    let session: AppSession

    var body: some View {
        Group {
            switch session.state {
            case .restoring:
                ProgressView("Checking membership...")
            case .signedOut:
                SignInView(session: session)
            case .requestingOTP(let email):
                SignInView(session: session, initialEmail: email)
            case .awaitingEmail(let email):
                CheckEmailView(session: session, email: email)
            case .pendingClaim:
                PendingClaimView(session: session)
            case .approved:
                ApprovedFamilyRootView(session: session)
                    .overlay {
                        if scenePhase != .active {
                            SensitiveContentCover()
                        }
                    }
            case .blocked:
                BlockedAccountView(session: session)
            case .failed(let error):
                SignInView(session: session, error: error)
            }
        }
        .onOpenURL { url in
            Task { await session.handleCallback(url) }
        }
    }
}

private struct ApprovedFamilyRootView: View {
    let session: AppSession

    var body: some View {
        ContentUnavailableView {
            Label("Membership approved", systemImage: "checkmark.seal.fill")
        } description: {
            Text("Your secure family view will appear after the verified family-data service is connected. No sample records are shown in production.")
        } actions: {
            Button("Sign out") {
                Task { await session.signOut() }
            }
            .buttonStyle(.bordered)
        }
        .privacySensitive()
    }
}

private struct BlockedAccountView: View {
    let session: AppSession

    var body: some View {
        ContentUnavailableView {
            Label("Account unavailable", systemImage: "person.crop.circle.badge.exclamationmark")
        } description: {
            Text("This membership cannot access family information. Contact a family administrator if you believe this is an error.")
        } actions: {
            Button("Sign out") {
                Task { await session.signOut() }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

private struct SensitiveContentCover: View {
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.largeTitle)
                Text("Bhargava Family")
                    .font(.headline)
            }
            .foregroundStyle(.secondary)
        }
        .accessibilityHidden(true)
    }
}
