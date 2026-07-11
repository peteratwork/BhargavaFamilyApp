import Foundation
import SwiftUI

enum VerificationStatus: String, Codable {
    case unverified
    case pending
    case verified

    var label: String {
        switch self {
        case .unverified: "Unverified"
        case .pending: "Pending review"
        case .verified: "Verified"
        }
    }
}

struct FamilyMember: Identifiable, Hashable, Codable {
    let id: String
    var fullName: String
    var dateOfBirth: Date
    var city: String
    var phoneNumber: String
    var parentIDs: [String]
    var spouseID: String?
    var verificationStatus: VerificationStatus
    var profileNote: String

    var givenName: String {
        fullName.components(separatedBy: " ").first ?? fullName
    }

    var age: Int {
        Calendar.current.dateComponents([.year], from: dateOfBirth, to: .now).year ?? 0
    }
}

struct MeetupEvent: Identifiable, Hashable {
    let id: UUID
    var title: String
    var city: String
    var date: Date
    var hostID: String
    var subgroup: String
    var attendeeIDs: [String]

    init(id: UUID = UUID(), title: String, city: String, date: Date, hostID: String, subgroup: String, attendeeIDs: [String]) {
        self.id = id
        self.title = title
        self.city = city
        self.date = date
        self.hostID = hostID
        self.subgroup = subgroup
        self.attendeeIDs = attendeeIDs
    }
}

struct RelationshipSummary: Identifiable, Hashable {
    let id = UUID()
    let member: FamilyMember
    let title: String
    let sharedAncestor: FamilyMember?
    let path: [FamilyMember]
    let score: Int
}

struct SignupDraft {
    var fullName = ""
    var dateOfBirth = Calendar.current.date(from: DateComponents(year: 1996, month: 1, day: 1)) ?? .now
    var city = ""
    var phoneNumber = ""
    var identityNote = ""
}

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case tree
    case discover
    case meetups
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .tree: "Tree"
        case .discover: "Discover"
        case .meetups: "Meetups"
        case .profile: "Profile"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .tree: "point.3.connected.trianglepath.dotted"
        case .discover: "location.magnifyingglass"
        case .meetups: "calendar.badge.plus"
        case .profile: "person.crop.circle"
        }
    }
}
