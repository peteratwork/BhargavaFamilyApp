# BhargavaFamilyApp

An Xcode-ready SwiftUI prototype for connecting members of the Bhargava clan.

## What is included

- Signup and profile claim flow with full name, date of birth, city, phone number, and an elder-verification note.
- Local sample family graph with parents, grandparents, siblings, first cousins, second cousins, and extended relationship labels.
- Family tree screen centered on the signed-in member and their grandparents.
- Nearby discovery that highlights relatives living in the same city and explains the relationship.
- Meetup creation and subgroup support.
- Lightweight gamification through a family score, nearby-relative count, cousin counts, and meetup activity.
- App Intents for Shortcuts/Siri entry points:
  - Find nearby Bhargava relatives.
  - Open a selected app section.

## Next production steps

- Add a backend store for members, relationships, identity claims, and meetup events.
- Use phone OTP plus trusted elder review before publishing a claimed true-name profile.
- Add privacy controls for phone visibility, city precision, and relationship visibility.
- Replace sample data with verified family records and import tools.
- Add tests around relationship calculations before scaling the graph.
