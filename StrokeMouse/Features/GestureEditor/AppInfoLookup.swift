import AppKit
import Foundation

/// Resolves macOS apps by bundle ID for scope UI (name, path, icon).
enum AppInfoLookup {
    struct Info: Identifiable, Hashable, Sendable {
        let bundleId: String
        let name: String
        /// Absolute path to the `.app` bundle; empty if not found.
        let path: String

        var id: String { bundleId }

        var displayPath: String {
            path.isEmpty ? bundleId : path
        }
    }

    // MARK: - Cache

    /// LaunchServices and icon lookups take tens of milliseconds cold (more on
    /// Intel Macs), and settings views call them per row and per sort
    /// comparison on every body pass. Results, including misses, stay cached
    /// until `invalidateCache()`, which settings call on open so apps
    /// installed or moved since then resolve again.
    private final class LookupCache: @unchecked Sendable {
        private let lock = NSLock()
        private var infos: [String: Info] = [:]
        private let icons: NSCache<NSString, NSImage> = {
            let cache = NSCache<NSString, NSImage>()
            cache.countLimit = 512
            return cache
        }()

        func info(for bundleId: String) -> Info? {
            lock.withLock { infos[bundleId] }
        }

        func store(_ info: Info, for bundleId: String) {
            lock.withLock { infos[bundleId] = info }
        }

        func icon(for path: String) -> NSImage? {
            icons.object(forKey: path as NSString)
        }

        func store(_ icon: NSImage, for path: String) {
            icons.setObject(icon, forKey: path as NSString)
        }

        func removeAll() {
            lock.withLock { infos.removeAll() }
            icons.removeAllObjects()
        }
    }

    private static let cache = LookupCache()

    static func invalidateCache() {
        cache.removeAll()
    }

    // MARK: - Resolve

    static func info(forBundleId bundleId: String) -> Info {
        let trimmed = bundleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Info(bundleId: trimmed, name: trimmed, path: "")
        }
        if let cached = cache.info(for: trimmed) {
            return cached
        }
        let resolved: Info
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: trimmed) {
            resolved = info(fromAppURL: url, fallbackBundleId: trimmed)
                ?? Info(bundleId: trimmed, name: trimmed, path: url.path)
        } else {
            resolved = Info(bundleId: trimmed, name: trimmed, path: "")
        }
        cache.store(resolved, for: trimmed)
        return resolved
    }

    /// Sorts bundle IDs by display name, resolving each name once instead of
    /// twice per comparison.
    static func sortedByName(
        _ bundleIds: [String],
        name: (String) -> String = { info(forBundleId: $0).name }
    ) -> [String] {
        bundleIds
            .map { (id: $0, name: name($0)) }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            .map(\.id)
    }

    static func info(fromAppURL url: URL, fallbackBundleId: String? = nil) -> Info? {
        guard url.pathExtension.lowercased() == "app" else { return nil }
        let bundle = Bundle(url: url)
        let bundleId = bundle?.bundleIdentifier
            ?? fallbackBundleId
            ?? url.deletingPathExtension().lastPathComponent
        guard !bundleId.isEmpty else { return nil }

        let displayName = FileManager.default.displayName(atPath: url.path)
        let name: String
        if let localized = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           !localized.isEmpty
        {
            name = localized
        } else if let short = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String,
                  !short.isEmpty
        {
            name = short
        } else {
            name = displayName
        }

        return Info(bundleId: bundleId, name: name, path: url.path)
    }

    /// Returns the same instance for repeated paths, so SwiftUI sees an
    /// unchanged image instead of re-rendering every icon on each pass.
    static func icon(for path: String) -> NSImage {
        if let cached = cache.icon(for: path) {
            return cached
        }
        let icon: NSImage
        if path.isEmpty {
            icon = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
                ?? NSImage(size: NSSize(width: 32, height: 32))
        } else {
            icon = NSWorkspace.shared.icon(forFile: path)
        }
        cache.store(icon, for: path)
        return icon
    }

    // MARK: - Scan installed apps

    /// Scans common application directories for `.app` bundles.
    static func scanInstalledApps() -> [Info] {
        let fileManager = FileManager.default
        var roots: [URL] = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
            URL(fileURLWithPath: NSHomeDirectory() + "/Applications", isDirectory: true),
        ]
        if let local = fileManager.urls(for: .applicationDirectory, in: .localDomainMask).first {
            roots.append(local)
        }

        return scanApplications(in: roots, maxDepth: 2)
    }

    /// Scans arbitrary folders (e.g. a game library chosen for an app group).
    static func scanApplications(in roots: [URL], maxDepth: Int) -> [Info] {
        var byBundleId: [String: Info] = [:]
        for root in roots {
            scanDirectory(root, depth: 0, maxDepth: maxDepth, into: &byBundleId)
        }

        return byBundleId.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func scanDirectory(
        _ directory: URL,
        depth: Int,
        maxDepth: Int,
        into result: inout [String: Info]
    ) {
        guard depth <= maxDepth else { return }
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for url in contents {
            let isApp = url.pathExtension.lowercased() == "app"
            if isApp {
                if let info = info(fromAppURL: url) {
                    // Prefer shorter /Applications paths over duplicates.
                    if let existing = result[info.bundleId] {
                        let preferNew = existing.path.hasPrefix("/System")
                            && !info.path.hasPrefix("/System")
                        if preferNew {
                            result[info.bundleId] = info
                        }
                    } else {
                        result[info.bundleId] = info
                    }
                }
                continue
            }

            // Descend into folders (e.g. /Applications/Utilities style nests).
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                let values = try? url.resourceValues(forKeys: [.isPackageKey])
                if values?.isPackage != true {
                    scanDirectory(url, depth: depth + 1, maxDepth: maxDepth, into: &result)
                }
            }
        }
    }
}
