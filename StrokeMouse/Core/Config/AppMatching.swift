import Foundation

/// Pure helpers for matching applications against `AppMatcher` values.
/// Bundle identifiers and paths compare case-insensitively (bundle IDs are
/// case-insensitive, and the default APFS volume is too).
enum AppMatching {
    static func normalizedBundleIdentifier(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Trims whitespace and collapses runs of `*`. A pattern must keep at least
    /// one literal character; a bare `*` is still valid and matches everything.
    static func normalizedPattern(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains(where: \.isWhitespace)
        else {
            return nil
        }
        var collapsed = ""
        for character in trimmed {
            if character == "*", collapsed.last == "*" { continue }
            collapsed.append(character)
        }
        return collapsed
    }

    static func isWildcardOnly(_ pattern: String) -> Bool {
        normalizedPattern(pattern) == "*"
    }

    /// Whole-string match where `*` stands for any (possibly empty) run of characters.
    static func matches(pattern: String, bundleIdentifier: String) -> Bool {
        guard let normalized = normalizedPattern(pattern) else { return false }
        return globMatches(
            pattern: normalized.lowercased(),
            value: bundleIdentifier.lowercased()
        )
    }

    /// Absolute, standardized directory path with a trailing slash, or nil.
    static func normalizedDirectory(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let expanded = (trimmed as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return nil }
        let standardized = URL(fileURLWithPath: expanded, isDirectory: true)
            .standardizedFileURL.path
        return standardized.hasSuffix("/") ? standardized : standardized + "/"
    }

    /// Directory forms to compare against: as written, symlink-resolved, and
    /// the `/var` `/private/var` aliases of each.
    static func directoryCandidates(_ raw: String) -> [String] {
        guard let normalized = normalizedDirectory(raw) else { return [] }
        let withoutSlash = normalized.hasSuffix("/")
            ? String(normalized.dropLast())
            : normalized
        return canonicalPathKeys(withoutSlash, asDirectory: true)
    }

    /// True when `path` lies strictly inside `directory` (component-wise, so
    /// `/Games` never matches `/Games2/App.app`). Symlinks are resolved on
    /// both the directory and the application path.
    static func path(_ path: String, isInside directory: String) -> Bool {
        let directories = directoryCandidates(directory)
        let applications = applicationPathCandidates(path)
        guard !directories.isEmpty, !applications.isEmpty else { return false }
        return applications.contains { application in
            directories.contains { application.hasPrefix($0) }
        }
    }

    static func normalizedApplicationPath(_ raw: String) -> String? {
        applicationPathCandidates(raw).first
    }

    /// Standardized path, symlink-resolved path, and their `/var` aliases.
    /// A missing trailing component still resolves: `resolvingSymlinksInPath`
    /// leaves the whole path untouched unless every component exists.
    static func applicationPathCandidates(_ raw: String) -> [String] {
        guard raw.hasPrefix("/") else { return [] }
        return canonicalPathKeys(raw, asDirectory: false)
    }

    private static func canonicalPathKeys(_ raw: String, asDirectory: Bool) -> [String] {
        let standardized = URL(fileURLWithPath: raw, isDirectory: asDirectory)
            .standardizedFileURL.path
        let resolved = resolvingExistingAncestors(standardized)
        var keys: [String] = []
        for path in [standardized, resolved] {
            for alias in volumeAliases(path) {
                var key = alias.lowercased()
                if asDirectory, !key.hasSuffix("/") {
                    key += "/"
                }
                if !keys.contains(key) {
                    keys.append(key)
                }
            }
        }
        return keys
    }

    /// Walk up to the longest existing ancestor, resolve its symlinks, then
    /// put the missing suffix back.
    private static func resolvingExistingAncestors(_ path: String) -> String {
        let fileManager = FileManager.default
        var url = URL(fileURLWithPath: path)
        var missing: [String] = []
        while url.path != "/", !fileManager.fileExists(atPath: url.path) {
            missing.append(url.lastPathComponent)
            url.deleteLastPathComponent()
        }
        var resolved = url.resolvingSymlinksInPath()
        for component in missing.reversed() {
            resolved.appendPathComponent(component)
        }
        return resolved.path
    }

    private static func volumeAliases(_ path: String) -> [String] {
        let pairs = [
            ("/private/var/", "/var/"),
            ("/private/tmp/", "/tmp/"),
        ]
        var results = [path]
        for (privatePrefix, shortPrefix) in pairs {
            let alias: String
            if path.hasPrefix(privatePrefix) {
                alias = shortPrefix + path.dropFirst(privatePrefix.count)
            } else if path.hasPrefix(shortPrefix) {
                alias = privatePrefix + path.dropFirst(shortPrefix.count)
            } else {
                continue
            }
            if !results.contains(alias) {
                results.append(alias)
            }
        }
        return results
    }

    /// Both arguments must already be lowercased and the pattern normalized.
    static func globMatches(pattern: String, value: String) -> Bool {
        let parts = pattern.split(separator: "*", omittingEmptySubsequences: false)
        guard parts.count > 1 else { return pattern == value }

        let first = parts[0]
        let last = parts[parts.count - 1]
        guard value.count >= first.count + last.count,
              value.hasPrefix(first),
              value.hasSuffix(last)
        else {
            return false
        }
        var searchStart = value.index(value.startIndex, offsetBy: first.count)
        let searchEnd = value.index(value.endIndex, offsetBy: -last.count)
        for part in parts.dropFirst().dropLast() where !part.isEmpty {
            guard searchStart <= searchEnd,
                  let found = value.range(
                    of: part,
                    range: searchStart..<searchEnd
                  )
            else {
                return false
            }
            searchStart = found.upperBound
        }
        return true
    }
}

/// Application rules compiled once per configuration so the event-tap thread
/// only performs string comparisons.
struct GestureAppRules: Equatable, Sendable {
    private struct CompiledMatcher: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            case exact(String)
            case pattern(String)
            case directory([String])
        }

        let kind: Kind

        init?(_ matcher: AppMatcher) {
            switch matcher.kind {
            case .bundleIdentifier:
                guard let id = AppMatching.normalizedBundleIdentifier(matcher.value) else {
                    return nil
                }
                kind = .exact(id.lowercased())
            case .bundleIdentifierPattern:
                guard let pattern = AppMatching.normalizedPattern(matcher.value) else {
                    return nil
                }
                kind = .pattern(pattern.lowercased())
            case .directory:
                let candidates = AppMatching.directoryCandidates(matcher.value)
                guard !candidates.isEmpty else { return nil }
                kind = .directory(candidates)
            }
        }

        func matches(bundleIdentifier: String?, path: String?) -> Bool {
            switch kind {
            case .exact(let expected):
                return bundleIdentifier?.lowercased() == expected
            case .pattern(let pattern):
                guard let bundleIdentifier else { return false }
                return AppMatching.globMatches(
                    pattern: pattern,
                    value: bundleIdentifier.lowercased()
                )
            case .directory(let candidates):
                guard let path else { return false }
                return AppMatching.applicationPathCandidates(path).contains { application in
                    candidates.contains { application.hasPrefix($0) }
                }
            }
        }
    }

    private struct CompiledGroup: Equatable, Sendable {
        let id: UUID
        let matchers: [CompiledMatcher]
        let suppressed: Set<GestureInputKind>
    }

    static let empty = GestureAppRules(policies: [], groups: [])

    private let policies: [String: Set<GestureInputKind>]
    private let groups: [CompiledGroup]

    init(policies: [AppGesturePolicy], groups: [AppGroup]) {
        var compiledPolicies: [String: Set<GestureInputKind>] = [:]
        for policy in policies {
            guard let id = AppMatching.normalizedBundleIdentifier(policy.bundleIdentifier),
                  !policy.suppressedGlobalInputs.isEmpty
            else {
                continue
            }
            compiledPolicies[id.lowercased(), default: []]
                .formUnion(policy.suppressedGlobalInputs.kinds)
        }
        self.policies = compiledPolicies
        self.groups = groups.map { group in
            CompiledGroup(
                id: group.id,
                matchers: group.matchers.compactMap(CompiledMatcher.init),
                suppressed: group.suppressedGlobalInputs.kinds
            )
        }
    }

    var isEmpty: Bool { policies.isEmpty && groups.isEmpty }

    func groupContains(
        _ groupID: UUID,
        bundleIdentifier: String?,
        path: String?
    ) -> Bool {
        guard let group = groups.first(where: { $0.id == groupID }) else {
            return false
        }
        return group.matchers.contains {
            $0.matches(bundleIdentifier: bundleIdentifier, path: path)
        }
    }

    func matchingGroupIDs(
        bundleIdentifier: String?,
        path: String?
    ) -> [UUID] {
        groups.compactMap { group in
            group.matchers.contains {
                $0.matches(bundleIdentifier: bundleIdentifier, path: path)
            } ? group.id : nil
        }
    }

    /// Union of the exact-application policy and every matching group:
    /// suppression always wins so a rule added to free an input stays effective.
    func suppressedGlobalInputs(
        bundleIdentifier: String?,
        path: String?
    ) -> Set<GestureInputKind> {
        guard !isEmpty else { return [] }
        var result = Set<GestureInputKind>()
        if let bundleIdentifier,
           let exact = policies[bundleIdentifier.lowercased()]
        {
            result.formUnion(exact)
        }
        for group in groups where !group.suppressed.isEmpty {
            if group.matchers.contains(where: {
                $0.matches(bundleIdentifier: bundleIdentifier, path: path)
            }) {
                result.formUnion(group.suppressed)
            }
        }
        return result
    }
}
