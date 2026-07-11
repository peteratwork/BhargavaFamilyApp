import Foundation
import Combine

@MainActor
final class FamilyStore: ObservableObject {
    @Published var members: [FamilyMember]
    @Published var currentMemberID: String
    @Published var meetups: [MeetupEvent]
    @Published var signupDraft = SignupDraft()

    init() {
        members = SampleFamily.members
        currentMemberID = "aanya"
        meetups = SampleFamily.meetups
    }

    var currentMember: FamilyMember {
        members.first { $0.id == currentMemberID } ?? members[0]
    }

    func member(id: String) -> FamilyMember? {
        members.first { $0.id == id }
    }

    func parents(of member: FamilyMember) -> [FamilyMember] {
        member.parentIDs.compactMap(member(id:))
    }

    func children(of member: FamilyMember) -> [FamilyMember] {
        members.filter { $0.parentIDs.contains(member.id) }
    }

    func grandparents(of member: FamilyMember) -> [FamilyMember] {
        parents(of: member).flatMap(parents(of:))
    }

    func siblings(of member: FamilyMember) -> [FamilyMember] {
        members.filter { candidate in
            candidate.id != member.id && !Set(candidate.parentIDs).isDisjoint(with: member.parentIDs)
        }
    }

    func relationships(from root: FamilyMember? = nil) -> [RelationshipSummary] {
        let person = root ?? currentMember
        return RelationshipEngine.relationships(from: person, members: members)
    }

    func nearbyRelationships() -> [RelationshipSummary] {
        relationships()
            .filter { $0.member.city.localizedCaseInsensitiveCompare(currentMember.city) == .orderedSame }
            .sorted { $0.score > $1.score }
    }

    func familyScore() -> Int {
        let verifiedBonus = members.filter { $0.verificationStatus == .verified }.count * 3
        let nearbyBonus = nearbyRelationships().count * 5
        return verifiedBonus + nearbyBonus + meetups.count * 8
    }

    func createMeetup(title: String, city: String, date: Date, subgroup: String) {
        let event = MeetupEvent(
            title: title,
            city: city,
            date: date,
            hostID: currentMemberID,
            subgroup: subgroup,
            attendeeIDs: [currentMemberID]
        )
        meetups.insert(event, at: 0)
    }

    func submitSignup() {
        guard !signupDraft.fullName.isEmpty, !signupDraft.city.isEmpty else { return }
        let id = signupDraft.fullName.lowercased().replacingOccurrences(of: " ", with: "-")
        let newMember = FamilyMember(
            id: id,
            fullName: signupDraft.fullName,
            dateOfBirth: signupDraft.dateOfBirth,
            city: signupDraft.city,
            phoneNumber: signupDraft.phoneNumber,
            parentIDs: [],
            spouseID: nil,
            verificationStatus: .pending,
            profileNote: signupDraft.identityNote
        )
        members.append(newMember)
        currentMemberID = id
        signupDraft = SignupDraft()
    }
}
