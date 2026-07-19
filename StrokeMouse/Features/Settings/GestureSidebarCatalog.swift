import Foundation

/// Sidebar node used by the gestures settings list.
enum GestureSidebarItem: Hashable, Sendable {
    case global
    case app(String)
}

/// Pure helpers for grouping / filtering gestures by app scope (unit-testable).
enum GestureSidebarCatalog {
    /// Bundle IDs that should appear in the sidebar: pinned ∪ referenced by any profile.
    static func sidebarAppBundleIds(
        gestures: [GestureProfile],
        pinnedBundleIds: [String]
    ) -> [String] {
        var ids = Set(pinnedBundleIds.compactMap(normalizedBundleId))
        for gesture in gestures {
            if case .apps(let bundleIds) = gesture.scope {
                for id in bundleIds {
                    if let normalized = normalizedBundleId(id) {
                        ids.insert(normalized)
                    }
                }
            }
        }
        return ids.sorted()
    }

    /// Gestures belonging to a sidebar node (before search / enabled filters).
    static func gestures(
        in item: GestureSidebarItem,
        from gestures: [GestureProfile]
    ) -> [GestureProfile] {
        switch item {
        case .global:
            return gestures.filter { $0.scope == .global }
        case .app(let bundleId):
            guard let target = normalizedBundleId(bundleId) else { return [] }
            return gestures.filter { profile in
                if case .apps(let ids) = profile.scope {
                    return ids.contains { normalizedBundleId($0) == target }
                }
                return false
            }
        }
    }

    /// Default scope when creating a new gesture under the selected sidebar node.
    static func defaultScope(for item: GestureSidebarItem) -> AppScope {
        switch item {
        case .global:
            return .global
        case .app(let bundleId):
            if let normalized = normalizedBundleId(bundleId) {
                return .apps([normalized])
            }
            return .global
        }
    }

    /// Preferred sidebar selection after saving a profile (first app id if multi-app).
    static func preferredSidebarItem(for scope: AppScope) -> GestureSidebarItem {
        switch scope {
        case .global:
            return .global
        case .apps(let ids):
            if let first = ids.compactMap(normalizedBundleId).first {
                return .app(first)
            }
            return .global
        }
    }

    /// Result of removing one app from the catalog.
    /// - Multi-app gestures: drop only that bundle id from `scope` (other apps keep the gesture).
    /// - Single-app gestures scoped solely to that app: delete the profile.
    struct RemoveAppPlan: Equatable, Sendable {
        var profilesToUpdate: [GestureProfile]
        var idsToDelete: Set<UUID>

        var isEmpty: Bool { profilesToUpdate.isEmpty && idsToDelete.isEmpty }
    }

    static func planRemoveApp(
        _ bundleId: String,
        from gestures: [GestureProfile]
    ) -> RemoveAppPlan {
        guard let target = normalizedBundleId(bundleId) else {
            return RemoveAppPlan(profilesToUpdate: [], idsToDelete: [])
        }

        var toUpdate: [GestureProfile] = []
        var toDelete = Set<UUID>()

        for profile in gestures {
            guard case .apps(let ids) = profile.scope else { continue }
            let normalized = ids.compactMap(normalizedBundleId)
            guard normalized.contains(target) else { continue }

            let remaining = normalized.filter { $0 != target }
            if remaining.isEmpty {
                toDelete.insert(profile.id)
            } else {
                var updated = profile
                updated.scope = .apps(remaining)
                toUpdate.append(updated)
            }
        }

        return RemoveAppPlan(profilesToUpdate: toUpdate, idsToDelete: toDelete)
    }

    private static func normalizedBundleId(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
