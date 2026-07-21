import SwiftUI
import BhargavaCore
import BhargavaSupabase

@main
struct BhargavaFamilyApp: App {
    var body: some Scene {
        WindowGroup {
            AppBootstrapView()
        }
    }
}

private struct AppBootstrapView: View {
    @State private var session: AppSession?
    @State private var configurationFailed = false
    @State private var attempt = 0

    var body: some View {
        Group {
            if let session {
                AuthenticationRootView(session: session)
            } else if configurationFailed {
                ConfigurationUnavailableView {
                    attempt += 1
                }
            } else {
                ProgressView("Starting securely...")
            }
        }
        .task(id: attempt) {
            await configure()
        }
    }

    @MainActor
    private func configure() async {
        configurationFailed = false

        do {
            let configuration = try AppConfiguration(values: [
                "SUPABASE_URL": Bundle.main.object(
                    forInfoDictionaryKey: "SupabaseURL"
                ) as? String ?? "",
                "SUPABASE_PUBLISHABLE_KEY": Bundle.main.object(
                    forInfoDictionaryKey: "SupabasePublishableKey"
                ) as? String ?? ""
            ])
            let callbackURL = URL(string: "bhargavafamily://auth-callback")!
            let repository = SupabaseAuthenticationRepository(
                configuration: configuration,
                callbackURL: callbackURL
            )
            let newSession = AppSession(repository: repository)
            session = newSession
            await newSession.restore()
        } catch {
            session = nil
            configurationFailed = true
        }
    }
}
