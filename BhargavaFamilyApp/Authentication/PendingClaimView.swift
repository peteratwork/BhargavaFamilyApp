import BhargavaCore
import SwiftUI

struct PendingClaimView: View {
    let session: AppSession

    var body: some View {
        ContentUnavailableView {
            Label("Membership review pending", systemImage: "person.badge.clock")
        } description: {
            Text("A trusted elder or administrator must approve your claim before family information becomes visible.")
        } actions: {
            VStack(spacing: 12) {
                Button("Check review status") {
                    Task { await session.refreshAccount() }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Refresh membership review status")

                Button("Sign out") {
                    Task { await session.signOut() }
                }
                .accessibilityLabel("Sign out")
            }
        }
    }
}
