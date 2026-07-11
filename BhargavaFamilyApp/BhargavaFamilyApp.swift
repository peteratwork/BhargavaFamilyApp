import SwiftUI

@main
struct BhargavaFamilyApp: App {
    @StateObject private var familyStore = FamilyStore()
    @StateObject private var intentRouter = AppIntentRouter.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(familyStore)
                .environmentObject(intentRouter)
        }
    }
}
