import Foundation

enum UpdateInstallReadiness: Equatable, Sendable {
    case ready
    case developmentMode
    case signingKeyMissing
    case updaterUnavailable
}

struct UpdateInstallEnvironment: Sendable {
    let bundlePathExtension: String
    let sparklePublicKey: String?
    let hasUpdater: Bool

    var readiness: UpdateInstallReadiness {
        guard bundlePathExtension.lowercased() == "app" else { return .developmentMode }
        guard Self.hasValidSparklePublicKey(sparklePublicKey) else { return .signingKeyMissing }
        guard hasUpdater else { return .updaterUnavailable }
        return .ready
    }

    func shouldCheckForUpdatesOnLaunch(automaticallyChecksForUpdates: Bool) -> Bool {
        automaticallyChecksForUpdates && readiness == .ready
    }

    static func hasValidSparklePublicKey(_ key: String?) -> Bool {
        guard let key else { return false }
        return !key.isEmpty && !key.contains("__")
    }
}
