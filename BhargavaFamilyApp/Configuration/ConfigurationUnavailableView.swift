import SwiftUI

struct ConfigurationUnavailableView: View {
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("App unavailable", systemImage: "lock.trianglebadge.exclamationmark")
        } description: {
            Text("The secure service configuration is unavailable. Try again or contact family support.")
        } actions: {
            Button("Try again", action: retry)
                .buttonStyle(.borderedProminent)
        }
    }
}
