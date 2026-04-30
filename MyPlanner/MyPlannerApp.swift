//
//  MyPlannerApp.swift
//  MyPlanner
//
//  App entry point. Sets up the SwiftData ModelContainer with all three
//  @Model types, registers UserDefaults defaults, and seeds default
//  categories on first launch.
//
//  CloudKit is intentionally DISABLED for v1 because the user has a free
//  Apple Developer account. The TODO block in `makeContainer()` shows
//  exactly which lines to change to flip on real iCloud sync once on a
//  paid account.
//

import SwiftUI
import SwiftData

@main
struct MyPlannerApp: App {
    let container: ModelContainer

    init() {
        AppSettingsDefaults.registerDefaults()
        self.container = MyPlannerApp.makeContainer()
        // Seed default categories on the main context if needed.
        let ctx = container.mainContext
        PlannerSeed.seedIfNeeded(context: ctx)
    }

    var body: some Scene {
        WindowGroup {
            RootShell()
                .environment(\.font, .system(size: 14))
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1100, height: 720)
        #endif
    }

    /// Build the SwiftData ModelContainer.
    ///
    /// =====================================================================
    /// TODO: CloudKit
    /// =====================================================================
    /// To enable iCloud sync once you upgrade to a paid Apple Developer
    /// account:
    ///
    ///   1. In Xcode, select the MyPlanner target → Signing & Capabilities,
    ///      click "+ Capability" and add **iCloud**. Tick **CloudKit** and
    ///      add a container (e.g. "iCloud.Coppola.MyPlanner").
    ///   2. Add the **Background Modes** capability and tick "Remote
    ///      notifications".
    ///   3. Replace the ModelConfiguration construction below with:
    ///
    ///         let config = ModelConfiguration(
    ///             schema: schema,
    ///             isStoredInMemoryOnly: false,
    ///             cloudKitDatabase: .private("iCloud.Coppola.MyPlanner")
    ///         )
    ///
    /// The model classes (Event, TaskItem, PlannerCategory) were intentionally
    /// designed to be CloudKit-friendly: every property has a default value,
    /// no required relationships, and `priority` is stored as a String
    /// instead of an enum. So no schema changes are needed.
    /// =====================================================================
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([
            Event.self,
            TaskItem.self,
            PlannerCategory.self,
        ])

        // === Local-only configuration (current default) ===
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        // === CloudKit configuration (uncomment after upgrading) ===
        // let config = ModelConfiguration(
        //     schema: schema,
        //     isStoredInMemoryOnly: false,
        //     cloudKitDatabase: .private("iCloud.Coppola.MyPlanner")
        // )

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
}
