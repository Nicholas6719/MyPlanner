//
//  AppSettings.swift
//  MyPlanner
//
//  App-wide settings (visible hour range, time format, accent override).
//
//  We keep settings in `UserDefaults` instead of in SwiftData so they are
//  trivially fast to read from any view via `@AppStorage`. A SwiftData
//  Settings record would also work but adds complexity (single-row
//  enforcement, model-context lookups), and these values don't need to
//  sync with CloudKit per-device anyway — each device picks its own
//  display preferences.
//

import Foundation
import SwiftUI

enum AppSettingsKeys {
    static let hourRangeStart = "hourRangeStart"
    static let hourRangeEnd   = "hourRangeEnd"
    static let timeFormat     = "timeFormat"      // "12h" or "24h"
    static let weekStart      = "weekStart"       // 0 = Sunday
    static let accentHex      = "accentHex"
    static let didSeed        = "didSeed"
    static let didRequestNotifAuth = "didRequestNotifAuth"
}

enum AppSettingsDefaults {
    static let hourRangeStart = 6
    static let hourRangeEnd   = 23
    static let timeFormat     = "12h"
    static let weekStart      = 0
    static let accentHex      = "#5eead4"

    /// Register defaults so `UserDefaults.standard.integer(forKey:)` returns
    /// the correct seed value before the user opens Settings.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            AppSettingsKeys.hourRangeStart: hourRangeStart,
            AppSettingsKeys.hourRangeEnd:   hourRangeEnd,
            AppSettingsKeys.timeFormat:     timeFormat,
            AppSettingsKeys.weekStart:      weekStart,
            AppSettingsKeys.accentHex:      accentHex,
        ])
    }
}
