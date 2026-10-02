import Foundation

extension PortableSettingsV1 {
    var mergeValues: [String: PortableSettingValue] {
        var values: [String: PortableSettingValue] = [
            "minStrokeDistance": .number(minStrokeDistance),
            "matchThreshold": .number(matchThreshold),
            "appearance": .string(appearance),
            "menuBarIconStyle": .string(menuBarIconStyle),
            "language": .string(language),
            "pinnedGestureAppBundleIds": .strings(pinnedGestureAppBundleIds),
            "showGestureHUD": .bool(showGestureHUD),
            "includeGestureHUDInCaptures": .bool(includeGestureHUDInCaptures),
            "directTrackpadEnabled": .bool(directTrackpadEnabled),
            "hudLineColor": .string(hudLineColor),
            "hudLineWidth": .number(hudLineWidth),
            "hudShowStartPoint": .bool(hudShowStartPoint),
            "hudStartPointRadius": .number(hudStartPointRadius),
            "showMatchToast": .bool(showMatchToast),
            "showMissToast": .bool(showMissToast),
            "showLiveMismatchFeedback": .bool(showLiveMismatchFeedback),
            "hudMismatchLineColor": .string(hudMismatchLineColor),
        ]
        if let ambiguityResolution {
            values["ambiguityResolution"] = .string(ambiguityResolution)
        }
        return values
    }

    func replacingMergeValues(
        _ values: [String: PortableSettingValue]
    ) throws -> PortableSettingsV1 {
        var result = self
        result.minStrokeDistance = try values.number("minStrokeDistance")
        result.matchThreshold = try values.number("matchThreshold")
        if let value = values["ambiguityResolution"] {
            guard case .string(let rawValue) = value else {
                throw ConfigurationSyncError.invalidStoredConfiguration
            }
            result.ambiguityResolution = rawValue
        }
        result.appearance = try values.string("appearance")
        result.menuBarIconStyle = try values.string("menuBarIconStyle")
        result.language = try values.string("language")
        result.pinnedGestureAppBundleIds = try values.strings(
            "pinnedGestureAppBundleIds"
        )
        result.showGestureHUD = try values.bool("showGestureHUD")
        result.includeGestureHUDInCaptures = try values.bool(
            "includeGestureHUDInCaptures"
        )
        result.directTrackpadEnabled = try values.bool("directTrackpadEnabled")
        result.hudLineColor = try values.string("hudLineColor")
        result.hudLineWidth = try values.number("hudLineWidth")
        result.hudShowStartPoint = try values.bool("hudShowStartPoint")
        result.hudStartPointRadius = try values.number("hudStartPointRadius")
        result.showMatchToast = try values.bool("showMatchToast")
        result.showMissToast = try values.bool("showMissToast")
        result.showLiveMismatchFeedback = try values.bool(
            "showLiveMismatchFeedback"
        )
        result.hudMismatchLineColor = try values.string(
            "hudMismatchLineColor"
        )
        try result.validate()
        return result
    }
}

private extension Dictionary where Key == String, Value == PortableSettingValue {
    func bool(_ key: String) throws -> Bool {
        guard case .bool(let value) = self[key] else {
            throw ConfigurationSyncError.invalidStoredConfiguration
        }
        return value
    }

    func number(_ key: String) throws -> Double {
        guard case .number(let value) = self[key] else {
            throw ConfigurationSyncError.invalidStoredConfiguration
        }
        return value
    }

    func string(_ key: String) throws -> String {
        guard case .string(let value) = self[key] else {
            throw ConfigurationSyncError.invalidStoredConfiguration
        }
        return value
    }

    func strings(_ key: String) throws -> [String] {
        guard case .strings(let value) = self[key] else {
            throw ConfigurationSyncError.invalidStoredConfiguration
        }
        return value
    }
}
