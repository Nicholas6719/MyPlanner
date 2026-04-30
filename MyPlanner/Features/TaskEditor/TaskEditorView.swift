//
//  TaskEditorView.swift
//  MyPlanner
//
//  Sheet/panel for creating or editing a TaskItem.
//

import SwiftUI
import SwiftData

struct TaskEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var categories: [PlannerCategory]

    @Bindable var task: TaskItem
    let isNew: Bool

    @State private var hasDueDate: Bool = false
    @State private var showDeleteConfirm = false
    @State private var customReminderInput = ""
    @State private var showCustomReminder = false

    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Title", text: $task.title) }

                Section("Due") {
                    Toggle("Has due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due",
                                   selection: Binding(
                                    get: { task.dueDate ?? Date() },
                                    set: { task.dueDate = $0 }))
                    }
                }

                Section("Details") {
                    Picker("Category", selection: $task.categoryID) {
                        Text("None").tag(UUID?.none)
                        ForEach(categories) { c in
                            Text(c.name).tag(UUID?.some(c.id))
                        }
                    }
                    SegmentedToggle(
                        options: [
                            (label: "Low",  value: "low"),
                            (label: "Med",  value: "med"),
                            (label: "High", value: "high"),
                        ],
                        selection: $task.priority
                    )
                    TextField("Notes", text: $task.notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                Section("Reminders") {
                    if !hasDueDate {
                        Text("Add a due date to set reminders.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.inkDim)
                    } else {
                        ForEach(task.reminderOffsetsMin.sorted(), id: \.self) { offset in
                            HStack {
                                Text(humanReminder(offset))
                                Spacer()
                                Button {
                                    task.reminderOffsetsMin.removeAll { $0 == offset }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(Theme.overdue)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        HStack(spacing: 8) {
                            quickAdd("1 day before", minutes: 24 * 60)
                            quickAdd("1 hour",       minutes: 60)
                            quickAdd("30 min",       minutes: 30)
                            quickAdd("Custom…",      minutes: nil)
                        }
                    }
                }

                if !isNew {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete Task", systemImage: "trash")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle(isNew ? "New Task" : "Edit Task")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(task.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                hasDueDate = task.dueDate != nil
            }
            .onChange(of: hasDueDate) { _, newValue in
                if newValue && task.dueDate == nil {
                    task.dueDate = Date()
                } else if !newValue {
                    task.dueDate = nil
                }
            }
            .alert("Delete this task?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) { delete() }
            } message: {
                Text("This cannot be undone.")
            }
            .alert("Reminder offset (minutes before)", isPresented: $showCustomReminder) {
                TextField("Minutes", text: $customReminderInput)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                Button("Add") {
                    if let m = Int(customReminderInput), m > 0 {
                        if !task.reminderOffsetsMin.contains(m) {
                            task.reminderOffsetsMin.append(m)
                            task.reminderOffsetsMin.sort()
                        }
                    }
                    customReminderInput = ""
                }
                Button("Cancel", role: .cancel) { customReminderInput = "" }
            }
        }
    }

    @ViewBuilder
    private func quickAdd(_ label: String, minutes: Int?) -> some View {
        Button(label) {
            if let m = minutes {
                if !task.reminderOffsetsMin.contains(m) {
                    task.reminderOffsetsMin.append(m)
                    task.reminderOffsetsMin.sort()
                }
                Task { await maybeRequestNotifAuth() }
            } else {
                showCustomReminder = true
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func save() {
        if isNew {
            modelContext.insert(task)
        }
        try? modelContext.save()
        Task { await reschedule() }
        dismiss()
    }

    private func delete() {
        modelContext.delete(task)
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
