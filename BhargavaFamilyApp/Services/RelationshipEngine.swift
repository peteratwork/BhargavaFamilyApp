import Foundation

enum RelationshipEngine {
    static func relationships(from root: FamilyMember, members: [FamilyMember]) -> [RelationshipSummary] {
        members
            .filter { $0.id != root.id }
            .compactMap { target in
                relationship(from: root, to: target, members: members)
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score { return lhs.member.fullName < rhs.member.fullName }
                return lhs.score > rhs.score
            }
    }

    static func relationship(from root: FamilyMember, to target: FamilyMember, members: [FamilyMember]) -> RelationshipSummary? {
        let rootParents = Set(root.parentIDs)
        let targetParents = Set(target.parentIDs)

        if root.parentIDs.contains(target.id) {
            return summary(target, "Parent", nil, [root, target], 100)
        }

        if target.parentIDs.contains(root.id) {
            return summary(target, "Child", nil, [root, target], 100)
        }

        if !rootParents.isDisjoint(with: targetParents) {
            let shared = rootParents.first { targetParents.contains($0) }.flatMap { member(id: $0, in: members) }
            let path = [root] + [shared].compactMap { $0 } + [target]
            return summary(target, "Sibling", shared, path, 95)
        }

        let rootAncestors = ancestorsByDistance(for: root, members: members)
        let targetAncestors = ancestorsByDistance(for: target, members: members)
        let sharedIDs = Set(rootAncestors.keys).intersection(Set(targetAncestors.keys))

        guard let sharedID = sharedIDs.min(by: {
            (rootAncestors[$0, default: 99] + targetAncestors[$0, default: 99]) <
                (rootAncestors[$1, default: 99] + targetAncestors[$1, default: 99])
        }) else {
            return nil
        }

        let rootDistance = rootAncestors[sharedID, default: 0]
        let targetDistance = targetAncestors[sharedID, default: 0]
        let shared = member(id: sharedID, in: members)
        let title = relationshipTitle(rootDistance: rootDistance, targetDistance: targetDistance)
        let score = max(15, 100 - ((rootDistance + targetDistance) * 12))
        let path = [root] + [shared].compactMap { $0 } + [target]
        return summary(target, title, shared, path, score)
    }

    private static func relationshipTitle(rootDistance: Int, targetDistance: Int) -> String {
        if rootDistance == 1 && targetDistance == 2 { return "Niece or Nephew" }
        if rootDistance == 2 && targetDistance == 1 { return "Aunt or Uncle" }
        if rootDistance == 2 && targetDistance == 2 { return "First cousin" }
        if rootDistance == 3 && targetDistance == 3 { return "Second cousin" }
        if rootDistance == targetDistance, rootDistance > 2 {
            return "\(ordinal(rootDistance - 1)) cousin"
        }
        if rootDistance >= 2 && targetDistance >= 2 {
            let cousinLevel = max(1, min(rootDistance, targetDistance) - 1)
            let removed = abs(rootDistance - targetDistance)
            if removed == 0 { return "\(ordinal(cousinLevel)) cousin" }
            return "\(ordinal(cousinLevel)) cousin \(removed)x removed"
        }
        return "Extended family"
    }

    private static func ancestorsByDistance(for member: FamilyMember, members: [FamilyMember]) -> [String: Int] {
        var result: [String: Int] = [:]
        var queue: [(String, Int)] = member.parentIDs.map { ($0, 1) }

        while let next = queue.first {
            queue.removeFirst()
            let (id, distance) = next
            guard result[id] == nil else { continue }
            result[id] = distance
            if let ancestor = self.member(id: id, in: members) {
                queue.append(contentsOf: ancestor.parentIDs.map { ($0, distance + 1) })
            }
        }

        return result
    }

    private static func summary(_ member: FamilyMember, _ title: String, _ ancestor: FamilyMember?, _ path: [FamilyMember], _ score: Int) -> RelationshipSummary {
        RelationshipSummary(member: member, title: title, sharedAncestor: ancestor, path: path, score: score)
    }

    private static func member(id: String, in members: [FamilyMember]) -> FamilyMember? {
        members.first { $0.id == id }
    }

    private static func ordinal(_ number: Int) -> String {
        switch number {
        case 1: "First"
        case 2: "Second"
        case 3: "Third"
        default: "\(number)th"
        }
    }
}
