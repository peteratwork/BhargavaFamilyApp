import Foundation

enum SampleFamily {
    static let members: [FamilyMember] = [
        FamilyMember(id: "hari", fullName: "Hari Prasad Bhargava", dateOfBirth: date(1942, 4, 12), city: "Jaipur", phoneNumber: "+91 90000 00001", parentIDs: [], spouseID: "kamla", verificationStatus: .verified, profileNote: "Elder record keeper for the Jaipur branch."),
        FamilyMember(id: "kamla", fullName: "Kamla Bhargava", dateOfBirth: date(1946, 9, 3), city: "Jaipur", phoneNumber: "+91 90000 00002", parentIDs: [], spouseID: "hari", verificationStatus: .verified, profileNote: "Maintains festival meetup lists."),
        FamilyMember(id: "mohan", fullName: "Mohan Bhargava", dateOfBirth: date(1968, 2, 18), city: "Delhi", phoneNumber: "+91 90000 00003", parentIDs: ["hari", "kamla"], spouseID: "savita", verificationStatus: .verified, profileNote: "Delhi chapter host."),
        FamilyMember(id: "savita", fullName: "Savita Bhargava", dateOfBirth: date(1971, 6, 8), city: "Delhi", phoneNumber: "+91 90000 00004", parentIDs: [], spouseID: "mohan", verificationStatus: .verified, profileNote: "Welcomes new members."),
        FamilyMember(id: "rekha", fullName: "Rekha Bhargava", dateOfBirth: date(1970, 12, 20), city: "Mumbai", phoneNumber: "+91 90000 00005", parentIDs: ["hari", "kamla"], spouseID: "arvind", verificationStatus: .verified, profileNote: "Mumbai meetup co-host."),
        FamilyMember(id: "arvind", fullName: "Arvind Bhargava", dateOfBirth: date(1967, 7, 29), city: "Mumbai", phoneNumber: "+91 90000 00006", parentIDs: [], spouseID: "rekha", verificationStatus: .verified, profileNote: "Family archive contributor."),
        FamilyMember(id: "nisha", fullName: "Nisha Bhargava", dateOfBirth: date(1995, 3, 14), city: "Bengaluru", phoneNumber: "+91 90000 00007", parentIDs: ["mohan", "savita"], spouseID: nil, verificationStatus: .verified, profileNote: "Runs career network group."),
        FamilyMember(id: "aanya", fullName: "Aanya Bhargava", dateOfBirth: date(1998, 11, 21), city: "Bengaluru", phoneNumber: "+91 90000 00008", parentIDs: ["mohan", "savita"], spouseID: nil, verificationStatus: .verified, profileNote: "Current signed-in member."),
        FamilyMember(id: "rohan", fullName: "Rohan Bhargava", dateOfBirth: date(1997, 5, 30), city: "Bengaluru", phoneNumber: "+91 90000 00009", parentIDs: ["rekha", "arvind"], spouseID: nil, verificationStatus: .verified, profileNote: "Nearby first cousin."),
        FamilyMember(id: "isha", fullName: "Isha Bhargava", dateOfBirth: date(2001, 1, 11), city: "Pune", phoneNumber: "+91 90000 00010", parentIDs: ["rekha", "arvind"], spouseID: nil, verificationStatus: .verified, profileNote: "Student group coordinator."),
        FamilyMember(id: "dev", fullName: "Dev Bhargava", dateOfBirth: date(1994, 8, 2), city: "Delhi", phoneNumber: "+91 90000 00011", parentIDs: ["nisha"], spouseID: nil, verificationStatus: .pending, profileNote: "Pending elder confirmation."),
        FamilyMember(id: "om", fullName: "Om Bhargava", dateOfBirth: date(1939, 10, 2), city: "Lucknow", phoneNumber: "+91 90000 00012", parentIDs: [], spouseID: "sarla", verificationStatus: .verified, profileNote: "Lucknow branch elder."),
        FamilyMember(id: "sarla", fullName: "Sarla Bhargava", dateOfBirth: date(1943, 1, 26), city: "Lucknow", phoneNumber: "+91 90000 00013", parentIDs: [], spouseID: "om", verificationStatus: .verified, profileNote: "Family cookbook curator."),
        FamilyMember(id: "pradeep", fullName: "Pradeep Bhargava", dateOfBirth: date(1966, 4, 7), city: "Bengaluru", phoneNumber: "+91 90000 00014", parentIDs: ["om", "sarla"], spouseID: "meera", verificationStatus: .verified, profileNote: "Bengaluru elder verifier."),
        FamilyMember(id: "meera", fullName: "Meera Bhargava", dateOfBirth: date(1969, 4, 28), city: "Bengaluru", phoneNumber: "+91 90000 00015", parentIDs: ["hari", "kamla"], spouseID: "pradeep", verificationStatus: .verified, profileNote: "Connects Jaipur and Lucknow branches."),
        FamilyMember(id: "kabir", fullName: "Kabir Bhargava", dateOfBirth: date(1999, 9, 19), city: "Bengaluru", phoneNumber: "+91 90000 00016", parentIDs: ["pradeep", "meera"], spouseID: nil, verificationStatus: .verified, profileNote: "Nearby first cousin through Meera."),
    ]

    static let meetups: [MeetupEvent] = [
        MeetupEvent(title: "Bengaluru Young Bhargavas Brunch", city: "Bengaluru", date: Calendar.current.date(byAdding: .day, value: 11, to: .now) ?? .now, hostID: "kabir", subgroup: "Young professionals", attendeeIDs: ["aanya", "rohan", "kabir", "nisha"]),
        MeetupEvent(title: "Jaipur Family Archive Day", city: "Jaipur", date: Calendar.current.date(byAdding: .day, value: 24, to: .now) ?? .now, hostID: "hari", subgroup: "Elders and record keepers", attendeeIDs: ["hari", "kamla", "meera"]),
        MeetupEvent(title: "Delhi Chapter Diwali Planning", city: "Delhi", date: Calendar.current.date(byAdding: .day, value: 42, to: .now) ?? .now, hostID: "mohan", subgroup: "Delhi chapter", attendeeIDs: ["mohan", "savita", "dev"])
    ]

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) ?? .now
    }
}
