//
//  EventEditorView.swift
//  MyPlanner
//
//  Sheet/panel for creating or editing an Event. Note: when `isNew` is
//  true, the caller passes an Event that has NOT been inserted into the
//  context yet — we insert on Save.
//

import SwiftUI
import SwiftData

struct EventEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var categories: [PlannerCategory]

    @Bindable var event: Event
    let isNew: Bool

    @State private var showDeleteConfirm = false
    @State private var customReminderInput = ""
    @State private var showCustomReminder = false

    var body: some View {
        NavigationStack {
            Form {
                titleSection
                whenSection
                detailsSection
                recurrenceSection
                remindersSection
                if !isNew { deleteSection }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle(isNew ? "New Event" : "Edit Event")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(event.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Delete this event?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) { }
                Button(deleteAlertButton, role: .destructive) { delete() }
            } message: {
                Text(event.recurrenceEnabled
                     ? "Delete this event and all repeats?"
                     : "This cannot be undone.")
            }
            .alert("Reminder offset (minutes before)", isPresented: $showCustomReminder) {
                TextField("Minutes", text: $customReminderInput)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                Button("Add") {
                    if let m = Int(customReminderInput), m > 0 {
                        if !event.reminderOffsetsMin.contains(m) {
                            event.reminderOffsetsMin.append(m)
                            event.reminderOffsetsMin.sort()
                        }
                    }
                    customReminderInput = ""
                }
                Button("Cancel", role: .cancel) { customReminderInput = "" }
            }
        }
    }

    private var deleteAlertButton: String {
        event.recurrenceEnabled ? "Delete All" : "Delete"
    }

    // MARK: - Sections

    private var titleSection: some View {
        Section {
            TextField("Title", text: $event.title)
        }
    }

    private var whenSection: some View {
        Section("When") {
            DatePicker("Starts", selection: $event.startDate)
            DatePicker("Ends",   selection: $event.endDate)
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            // Picker selection uses an OPTIONAL UUID directly so "None" is
            // simply `nil` and we don't need a sentinel. Picker handles
            // optionals fine when every tag is `UUID?`.
            Picker("Category", selection: $event.categoryID) {
                Text("None").tag(UUID?.none)
                ForEach(categories) { c in
                    Text(c.name).tag(UUID?.some(c.id))
                }
            }
            TextField("Notes / Location", text: $event.notes, axis: .vertical)
                .lineLimit(2...6)
        }
    }

    private var recurrenceSection: some View {
        Section("Repeat weekly") {
            SegmentedToggle(
                options: [
                    (label: "Off", value: false),
                    (label: "On",  value: true),
                ],
                selection: $event.recurrenceEnabled
            )
            if event.recurrenceEnabled {
                WeekdayPicker(selection: $event.recurrenceByDay)
                DatePicker("Repeat until",
                           selection: Binding(
                            get: { event.recurrenceUntil ?? Date().addingTimeInterval(90 * 24 * 3600) },
                            set: { event.recurrenceUntil = $0 }),
                           displayedComponents: .date)
                Button("Clear repeat-until") {
                    event.recurrenceUntil = nil
                }
                .foregroundStyle(Theme.inkDim)
            }
        }
    }

    private var remindersSection: some View {
        Section("Reminders") {
            ForEach(event.reminderOffsetsMin.sorted(), id: \.self) { offset in
                HStack {
                    Text(humanReminder(offset))
                    Spacer()
                    Button {
                        event.reminderOffsetsMin.removeAll { $0 == offset }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(Theme.overdue)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                quickAdd("1 day before",  minutes: 24 * 60)
                quickAdd("1 hour",        minutes: 60)
                quickAdd("30 min",        minutes: 30)
                quickAdd("Custom…",       minutes: nil)
            }
        }
    }

    @ViewBuilder
    private func quickAdd(_ label: String, minutes: Int?) -> some View {
        Button(label) {
            if let m = minutes {
                if !event.reminderOffsetsMin.contains(m) {
                    event.reminderOffsetsMin.append(m)
                    event.reminderOffsetsMin.sort()
                }
                Task { await maybeRequestNotifAuth() }
            } else {
                showCustomReminder = true
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete Event", systemImage: "trash")
            }
        }
    }

    // MARK: - Actions

    private func save() {
        // Make sure end >= start
        if event.endDate < event.startDate {
            event.endDate = event.startDate.addingTimeInterval(3600)
        }
        if isNew {
            modelContext.insert(event)
        }
        try? modelContext.save()
        Task { await reschedule() }
        dismiss()
    }

    private func delete() {
        modelContext.delete(event)
        try? modelContext.save()
        Task { await reschedule() }
        dismiss()
    }

    private func reschedule() async {
        let events = (try? modelContext.fetch(FetchDescriptor<Event>())) ?? []
        let tasks = (try? modelContext.fetch(FetchDescriptor<TaskItem>())) ?? []
        await NotificationScheduler.reschedule(events: events, tasks: tasks)
    }

    private func maybeRequestNotifAuth() async {
        let asked = UserDefaults.standard.bool(forKey: AppSettingsKeys.didRequestNotifAuth)
        guard !asked else { return }
        UserDefaults.standard.set(true, forKey: AppSettingsKeys.didRequestNotifAuth)
        _ = await NotificationScheduler.requestAuthorization()
    }

    private func humanReminder(_ offsetMin: Int) -> String {
        if offsetMin >= 24 * 60 && offsetMin % (24 * 60) == 0 {
            let days = offsetMin / (24 * 60)
            return "\(days) day\(days == 1 ? "" : "s") before"
        }
        if offsetMin >= 60 && offsetMin % 60 == 0 {
            let h = offsetMin / 60
            return "\(h) hour\(h == 1 ? "" : "s") before"
        }
        return "\(offsetMin) min before"
    }
}
