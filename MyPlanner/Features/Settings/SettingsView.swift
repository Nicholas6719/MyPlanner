//
//  SettingsView.swift
//  MyPlanner
//
//  Notifications, display, categories, backup, danger zone.
//

import SwiftUI
import SwiftData
import UserNotifications
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var categories: [PlannerCategory]
    @Query private var events: [Event]
    @Query private var tasks: [TaskItem]

    @AppStorage(AppSettingsKeys.hourRangeStart) private var hourStart: Int = AppSettingsDefaults.hourRangeStart
    @AppStorage(AppSettingsKeys.hourRangeEnd) private var hourEnd: Int = AppSettingsDefaults.hourRangeEnd

    @State private var notifStatus: UNAuthorizationStatus = .notDetermined
    @State private var exportURL: URL?
    @State private var showImporter = false
    @State private var pendingImportData: Data?
    @State private var showImportConfirm = false
    @State private var showResetConfirm = false
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            Form {
                notificationsSection
                displaySection
                categoriesSection
                backupSection
                dangerSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await refreshNotifStatus() }
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.json],
                      allowsMultipleSelection: false) { result in
            handleImportResult(result)
        }
        .alert("Replace all data?", isPresented: $showImportConfirm) {
            Button("Cancel", role: .cancel) { pendingImportData = nil }
            Button("Replace", role: .destructive) { performImport() }
        } message: {
            Text("Importing will permanently replace your current events, tasks, and categories.")
        }
        .alert("Reset all data?", isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) { resetAll() }
        } message: {
            Text("This deletes every event, task, and custom category. Defaults will be restored.")
        }
        .alert("Import failed", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        Section("Notifications") {
            HStack {
                Text("Status")
                Spacer()
                Text(statusLabel)
                    .foregroundStyle(statusColor)
                    .font(.system(size: 13, weight: .medium))
            }
            if notifStatus != .authorized && notifStatus != .provisional {
                Button("Enable Notifications") {
                    Task {
                        _ = await NotificationScheduler.requestAuthorization()
                        await refreshNotifStatus()
                    }
                }
            }
            Text("Reminders are local-only. They fire reliably as long as the app has been opened at least once after they were created.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkDim)
        }
    }

    private var statusLabel: String {
        switch notifStatus {
        case .authorized:    return "Enabled"
        case .provisional:   return "Provisional"
        case .ephemeral:     return "Ephemeral"
        case .denied:        return "Blocked — check Settings"
        case .notDetermined: return "Not yet enabled"
        @unknown default:    return "Unknown"
        }
    }

    private var statusColor: Color {
        switch notifStatus {
        case .authorized, .provisional: return Theme.accent
        case .denied:                   return Theme.overdue
        default:                        return Theme.inkDim
        }
    }

    private func refreshNotifStatus() async {
        notifStatus = await NotificationScheduler.currentStatus()
    }

    // MARK: - Display

    private var displaySection: some View {
        Section("Display") {
            Picker("Visible hours start", selection: $hourStart) {
                ForEach(0..<24, id: \.self) { h in
                    Text(formatHour(h)).tag(h)
                }
            }
            Picker("Visible hours end", selection: $hourEnd) {
                ForEach(0..<24, id: \.self) { h in
                    Text(formatHour(h)).tag(h)
                }
            }
            .onChange(of: hourEnd) { _, _ in
                if hourEnd < hourStart { swap(&hourStart, &hourEnd) }
            }
            .onChange(of: hourStart) { _, _ in
                if hourEnd < hourStart { swap(&hourStart, &hourEnd) }
            }
        }
    }

    private func formatHour(_ h: Int) -> String {
        let suffix = h < 12 ? "am" : "pm"
        let display = h == 0 ? 12 : (h <= 12 ? h : h - 12)
        return "\(display)\(suffix)"
    }

    // MARK: - Categories

    private var categoriesSection: some View {
        Section("Categories") {
            ForEach(categories) { c in
                CategoryRow(category: c) {
                    delete(category: c)
                }
            }
            Button {
                let new = PlannerCategory(name: "New", colorHex: "#94a3b8")
                modelContext.insert(new)
                try? modelContext.save()
            } label: {
                Label("Add Category", systemImage: "plus.circle.fill")
            }
        }
    }

    private func delete(category: PlannerCategory) {
        // Nullify references on events/tasks (don't crash, per spec).
        for e in events where e.categoryID == category.id { e.categoryID = nil }
        for t in tasks where t.categoryID == category.id { t.categoryID = nil }
        modelContext.delete(category)
        try? modelContext.save()
    }

    // MARK: - Backup

    private var backupSection: some View {
        Section("Backup") {
            HStack(spacing: 12) {
                Button {
                    exportNow()
                } label: {
                    Label("Export JSON", systemImage: "square.and.arrow.up")
                }
                Button {
                    showImporter = true
                } label: {
                    Label("Import JSON", systemImage: "square.and.arrow.down")
                }
            }
            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Share \(exportURL.lastPathComponent)",
                          systemImage: "paperplane")
                }
            }
            Text("Use Export → AirDrop / Save to Files / iCloud Drive → Import on another device. This is the manual sync workflow until CloudKit is enabled.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkDim)
        }
    }

    private func exportNow() {
        do {
            let data = try BackupService.export(events: events,
                                                tasks: tasks,
                                                categories: categories)
            exportURL = try BackupService.writeExportToTempFile(data)
        } catch {
            importError = "Could not export: \(error.localizedDescription)"
        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            // We need security-scoped access for the picked file.
            let needsRelease = url.startAccessingSecurityScopedResource()
            defer { if needsRelease { url.stopAccessingSecurityScopedResource() } }
            do {
                pendingImportData = try Data(contentsOf: url)
                showImportConfirm = true
            } catch {
                importError = "Could not read file: \(error.localizedDescription)"
            }
        case .failure(let err):
            importError = err.localizedDescription
        }
    }

    private func performImport() {
        guard let data = pendingImportData else { return }
        do {
            try BackupService.importReplacing(data, into: modelContext)
        } catch {
            importError = "Import failed: \(error.localizedDescription)"
        }
        pendingImportData = nil
        Task {
            let events = (try? modelContext.fetch(FetchDescriptor<Event>())) ?? []
            let tasks = (try? modelContext.fetch(FetchDescriptor<TaskItem>())) ?? []
            await NotificationScheduler.reschedule(events: events, tasks: tasks)
        }
    }

    // MARK: - Danger zone

    private var dangerSection: some View {
        Section("Danger Zone") {
            Button(role: .destructive) {
                showResetConfirm = true
            } label: {
                Label("Reset all data", systemImage: "trash")
            }
        }
    }

    private func resetAll() {
        try? modelContext.delete(model: Event.self)
        try? modelContext.delete(model: TaskItem.self)
        try? modelContext.delete(model: PlannerCategory.self)
        try? modelContext.save()
        UserDefaults.standard.set(false, forKey: AppSettingsKeys.didSeed)
        PlannerSeed.seedIfNeeded(context: modelContext)
        Task { await NotificationScheduler.reschedule(events: [], tasks: []) }
    }
}

// MARK: - Category Row

private struct CategoryRow: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var category: PlannerCategory
    let onDelete: () -> Void

    @State private var pickerOpen = false
    @State private var pickedColor: Color = .gray

    var body: some View {
        HStack(spacing: 10) {
            Button {
                pickedColor = Color(hex: category.colorHex)
                pickerOpen = true
            } label: {
                Circle()
                    .fill(Color(hex: category.colorHex))
                    .frame(width: 22, height: 22)
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)

            TextField("Name", text: $category.name, onCommit: {
                try? modelContext.save()
            })

            Button {
                onDelete()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(Theme.overdue)
            }
            .buttonStyle(.plain)
        }
        .popover(isPresented: $pickerOpen) {
            VStack(spacing: 12) {
                ColorPicker("Color", selection: $pickedColor, supportsOpacity: false)
                    .labelsHidden()
                Button("Done") {
                    category.colorHex = pickedColor.toHex()
                    try? modelContext.save()
                    pickerOpen = false
                }
            }
            .padding()
        }
    }
}
