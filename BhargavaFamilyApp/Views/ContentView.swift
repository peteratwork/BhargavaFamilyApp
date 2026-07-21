import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var intentRouter: AppIntentRouter
    @State private var selectedTab: AppTab = .home
    let onSignOut: () -> Void

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(selectedTab: $selectedTab)
                .tabItem { Label(AppTab.home.title, systemImage: AppTab.home.symbol) }
                .tag(AppTab.home)

            FamilyTreeView()
                .tabItem { Label(AppTab.tree.title, systemImage: AppTab.tree.symbol) }
                .tag(AppTab.tree)

            DiscoverView()
                .tabItem { Label(AppTab.discover.title, systemImage: AppTab.discover.symbol) }
                .tag(AppTab.discover)

            MeetupsView()
                .tabItem { Label(AppTab.meetups.title, systemImage: AppTab.meetups.symbol) }
                .tag(AppTab.meetups)

            ProfileView(onSignOut: onSignOut)
                .tabItem { Label(AppTab.profile.title, systemImage: AppTab.profile.symbol) }
                .tag(AppTab.profile)
        }
        .tint(.indigo)
        .onReceive(intentRouter.$requestedTab.compactMap { $0 }) { tab in
            selectedTab = tab
            intentRouter.requestedTab = nil
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var store: FamilyStore
    @Binding var selectedTab: AppTab

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Namaste, \(store.currentMember.givenName)")
                            .font(.largeTitle.bold())
                        Text("Stay close to your Bhargava family, find how people are connected, and discover relatives nearby.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.indigo.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        StatCard(title: "Family score", value: "\(store.familyScore())", symbol: "sparkles")
                        StatCard(title: "Nearby relatives", value: "\(store.nearbyRelationships().count)", symbol: "mappin.and.ellipse")
                        StatCard(title: "First cousins", value: "\(store.relationships().filter { $0.title == "First cousin" }.count)", symbol: "person.2.fill")
                        StatCard(title: "Meetups", value: "\(store.meetups.count)", symbol: "calendar")
                    }

                    SectionHeader("Nearby connections")
                    ForEach(store.nearbyRelationships().prefix(3)) { relation in
                        RelationshipRow(summary: relation)
                    }

                    HStack(spacing: 12) {
                        Button {
                            selectedTab = .discover
                        } label: {
                            Label("Find relatives", systemImage: "location.magnifyingglass")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            selectedTab = .meetups
                        } label: {
                            Label("Plan meetup", systemImage: "calendar.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
            }
            .navigationTitle("Bhargava Family")
        }
    }
}

struct FamilyTreeView: View {
    @EnvironmentObject private var store: FamilyStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    TreeGeneration(title: "Grandparents", members: store.grandparents(of: store.currentMember))
                    TreeConnector()
                    TreeGeneration(title: "Parents", members: store.parents(of: store.currentMember))
                    TreeConnector()
                    TreeGeneration(title: "You and siblings", members: [store.currentMember] + store.siblings(of: store.currentMember))

                    SectionHeader("Extended under shared grandparents")
                    ForEach(store.relationships().filter { $0.title.contains("cousin") }.prefix(8)) { relation in
                        RelationshipRow(summary: relation)
                    }
                }
                .padding()
            }
            .navigationTitle("Family Tree")
        }
    }
}

struct DiscoverView: View {
    @EnvironmentObject private var store: FamilyStore
    @State private var showingNearbyOnly = true

    private var results: [RelationshipSummary] {
        showingNearbyOnly ? store.nearbyRelationships() : store.relationships()
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: $showingNearbyOnly) {
                        Label("Relatives in \(store.currentMember.city)", systemImage: "mappin.circle")
                    }
                }

                Section("Relationship matches") {
                    ForEach(results) { relation in
                        RelationshipRow(summary: relation)
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    }
                }
            }
            .navigationTitle("Discover")
        }
    }
}

struct MeetupsView: View {
    @EnvironmentObject private var store: FamilyStore
    @State private var title = ""
    @State private var city = ""
    @State private var subgroup = "Young professionals"
    @State private var date = Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now

    var body: some View {
        NavigationStack {
            List {
                Section("Create meetup") {
                    TextField("Title", text: $title)
                    TextField("City", text: $city)
                    TextField("Subgroup", text: $subgroup)
                    DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    Button {
                        store.createMeetup(title: title, city: city.isEmpty ? store.currentMember.city : city, date: date, subgroup: subgroup)
                        title = ""
                        city = ""
                    } label: {
                        Label("Create meetup", systemImage: "plus.circle.fill")
                    }
                    .disabled(title.isEmpty)
                }

                Section("Upcoming") {
                    ForEach(store.meetups) { meetup in
                        MeetupRow(meetup: meetup)
                    }
                }
            }
            .navigationTitle("Meetups")
        }
    }
}

struct ProfileView: View {
    @EnvironmentObject private var store: FamilyStore
    let onSignOut: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Current profile") {
                    LabeledContent("Name", value: store.currentMember.fullName)
                    LabeledContent("City", value: store.currentMember.city)
                    LabeledContent("Phone", value: store.currentMember.phoneNumber)
                    LabeledContent("Verification", value: store.currentMember.verificationStatus.label)
                }

                Section {
                    Button("Sign out", role: .destructive, action: onSignOut)
                }

                Section {
                    TextField("Full legal name", text: $store.signupDraft.fullName)
                    DatePicker("Date of birth", selection: $store.signupDraft.dateOfBirth, displayedComponents: .date)
                    TextField("Current residence", text: $store.signupDraft.city)
                    TextField("Phone number", text: $store.signupDraft.phoneNumber)
                        .keyboardType(.phonePad)
                    TextField("Identity note for elder verifier", text: $store.signupDraft.identityNote, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                    Button {
                        store.submitSignup()
                    } label: {
                        Label("Submit for verification", systemImage: "checkmark.seal")
                    }
                } header: {
                    Text("Sign up or claim profile")
                } footer: {
                    Text("A real backend should verify phone ownership and route the true-name claim to trusted family elders before publishing it.")
                }
            }
            .navigationTitle("Profile")
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.indigo)
            Text(value)
                .font(.title.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
    }
}

struct RelationshipRow: View {
    let summary: RelationshipSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading) {
                    Text(summary.member.fullName)
                        .font(.headline)
                    Text("\(summary.title) in \(summary.member.city)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(summary.score)")
                    .font(.headline.monospacedDigit())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.green.opacity(0.12), in: Capsule())
            }

            if let sharedAncestor = summary.sharedAncestor {
                Text("Shared ancestor: \(sharedAncestor.fullName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct TreeGeneration: View {
    let title: String
    let members: [FamilyMember]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(members) { member in
                    VStack(spacing: 6) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.indigo)
                        Text(member.fullName)
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.center)
                        Text(member.city)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 116)
                    .padding(10)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                }
            }
        }
    }
}

struct TreeConnector: View {
    var body: some View {
        Image(systemName: "arrow.down")
            .font(.title3.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
    }
}

struct MeetupRow: View {
    @EnvironmentObject private var store: FamilyStore
    let meetup: MeetupEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(meetup.title)
                .font(.headline)
            Text("\(meetup.city) - \(meetup.subgroup)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(meetup.date.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
            Text("\(meetup.attendeeIDs.count) attending")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct SectionHeader: View {
    private let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    ContentView(onSignOut: {})
        .environmentObject(FamilyStore())
        .environmentObject(AppIntentRouter.shared)
}
