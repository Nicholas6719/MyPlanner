//
//  PlannerSeed.swift
//  MyPlanner
//
//  Inserts default categories on first launch. Idempotent: only runs once
//  thanks to a UserDefaults flag.
//

import Foundation
import SwiftData

enum PlannerSeed {

    static func seedIfNeeded(context: ModelContext) {
        let didSeed = UserDefaults.standard.bool(forKey: AppSettingsKeys.didSeed)
        guard !didSeed else { return }

        // Check that categories are actually empty — defensive in case the
        // user wiped data via "Reset all data". If a real category exists
        // we don't want to add duplicates of "Work"/"Class"/etc.
        let descriptor = FetchDescriptor<PlannerCategory>()
        let existing = (try? context.fetch(descriptor)) ?? []

        let defaults: [(String, String)] = [
            ("Work",     "#5eead4"),
            ("Class",    "#a78bfa"),
            ("Personal", "#fbbf24"),
            ("Health",   "#f87171"),
        ]

        for (name, hex) in defaults {
            if !existing.contains(where: { $0.name == name }) {
                context.insert(PlannerCategory(name: name, colorHex: hex))
            }
        }

        try? context.save()
        UserDefaults.standard.set(true, forKey: AppSettingsKeys.didSeed)
    }
}
