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

    // MARK: - Resolve

    static func info(forBundleId bundleId: String) -> Info {
        let trimmed = bundleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Info(bundleId: trimmed, name: trimmed, path: "")
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: trimmed) {
            return info(fromAppURL: url, fallbackBundleId: trimmed)
                ?? Info(bundleId: trimmed, name: trimmed, path: url.path)
        }
        return Info(bundleId: trimmed, name: trimmed, path: "")
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

    static func icon(for path: String) -> NSImage {
        if path.isEmpty {
            return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
                ?? NSImage(size: NSSize(width: 32, height: 32))
        }
        return NSWorkspace.shared.icon(forFile: path)
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

        var byBundleId: [String: Info] = [:]
        for root in roots {
            scanDirectory(root, depth: 0, maxDepth: 2, into: &byBundleId)
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
