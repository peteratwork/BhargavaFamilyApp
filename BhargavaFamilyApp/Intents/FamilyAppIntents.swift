import AppIntents
import Combine
import Foundation

final class AppIntentRouter: ObservableObject {
    static let shared = AppIntentRouter()
    @Published var requestedTab: AppTab?

    private init() {}
}

enum FamilySectionIntentValue: String, AppEnum {
    case home
    case tree
    case discover
    case meetups
    case profile

    static var typeDisplayName: LocalizedStringResource { "Family section" }
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Family section"

    static var caseDisplayRepresentations: [FamilySectionIntentValue: DisplayRepresentation] {
        [
            .home: "Home",
            .tree: "Family Tree",
            .discover: "Discover Relatives",
            .meetups: "Meetups",
            .profile: "Profile"
        ]
    }

    var tab: AppTab {
        switch self {
        case .home: .home
        case .tree: .tree
        case .discover: .discover
        case .meetups: .meetups
        case .profile: .profile
        }
    }
}

struct OpenFamilySectionIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Bhargava family section"
    static let description = IntentDescription("Open Bhargava Family App to a selected family section.")
    static let openAppWhenRun = true

    @Parameter(title: "Section")
    var section: FamilySectionIntentValue

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            AppIntentRouter.shared.requestedTab = section.tab
        }
        return .result()
    }
}

struct NearbyRelativeEntity: AppEntity, Identifiable {
    let id: String
    let name: String
    let relationship: String
    let city: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Nearby relative"
    static let defaultQuery = NearbyRelativeQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(relationship) in \(city)"
        )
    }
}

struct NearbyRelativeQuery: EntityQuery {
    func entities(for identifiers: [NearbyRelativeEntity.ID]) async throws -> [NearbyRelativeEntity] {
        let entities = try await suggestedEntities()
        return entities.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [NearbyRelativeEntity] {
        await MainActor.run {
            let store = FamilyStore()
            return store.nearbyRelationships().map {
                NearbyRelativeEntity(
                    id: $0.member.id,
                    name: $0.member.fullName,
                    relationship: $0.title,
                    city: $0.member.city
                )
            }
        }
    }
}

struct FindNearbyBhargavasIntent: AppIntent {
    static let title: LocalizedStringResource = "Find nearby Bhargava relatives"
    static let description = IntentDescription("Open the app to relatives living near you.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            AppIntentRouter.shared.requestedTab = .discover
        }
        return .result()
    }
}

struct BhargavaFamilyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: FindNearbyBhargavasIntent(),
            phrases: [
                "Find nearby Bhargavas in \(.applicationName)",
                "Show my nearby relatives in \(.applicationName)"
            ],
            shortTitle: "Nearby Relatives",
            systemImageName: "location.magnifyingglass"
        )

        AppShortcut(
            intent: OpenFamilySectionIntent(),
            phrases: [
                "Open family tree in \(.applicationName)",
                "Open Bhargava meetups in \(.applicationName)"
            ],
            shortTitle: "Open Section",
            systemImageName: "point.3.connected.trianglepath.dotted"
        )
    }
}
