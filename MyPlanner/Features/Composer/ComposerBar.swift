//
//  ComposerBar.swift
//  MyPlanner
//
//  The bottom-of-screen text input where the user types things like
//  "Working Monday 7am to 3:30pm". Shows a live ParsePreview as the user
//  types, commits on Enter or send tap.
//

import SwiftUI
import SwiftData

struct ComposerBar: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var categories: [PlannerCategory]

    @State private var text: String = ""
    @State private var typeOverride: PreviewKind?
    @State private var parsed: ParsedInput?
    @FocusState private var focused: Bool

    /// State for the date-prompt sheet. Shown when the user commits a
    /// task without a date, or overrides Task → Event without a date —
    /// in both cases we'd otherwise have to silently guess.
    @State private var pendingTitle: String?
    @State private var pendingCategory: UUID?
    @State private var pendingKind: DatePromptKind = .task
    @State private var showDuePrompt = false

    var body: some View {
        VStack(spacing: 8) {
            if !text.isEmpty, let parsed {
                ParsePreview(parsed: parsed,
                             categories: categories,
                             typeOverride: $typeOverride)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            inputRow
        }
        .padding(.horizontal, Theme.Spacing.outer)
        .padding(.bottom, Theme.Spacing.tight)
        .background(
            // Pull a subtle gradient over the system blur so the composer
            // visually separates from the content behind it.
            LinearGradient(
                colors: [Color.clear, Theme.bg.opacity(0.95)],
                startPoint: .top,
                endPoint: .bottom)
                .allowsHitTesting(false)
        )
        .onChange(of: text) { _, new in
            recomputePreview(new)
        }
        .animation(.easeOut(duration: 0.18), value: text.isEmpty)
        .sheet(isPresented: $showDuePrompt) {
            TaskDueDatePrompt(
                title: pendingTitle ?? "",
                kind: pendingKind
            ) { date in
                if let title = pendingTitle {
                    switch pendingKind {
                    case .task:
                        insertTask(title: title,
                                   due: date,
                                   category: pendingCategory)
                    case .event:
                        // Default a chosen date to 9am for 1 hour. If
                        // they picked nil ("save without date"), fall
                        // back to next-hour-from-now.
                        let start: Date = {
                            if let d = date {
                                var comps = Calendar.current
                                    .dateComponents([.year, .month, .day], from: d)
                                comps.hour = 9
                                comps.minute = 0
                                return Calendar.current.date(from: comps) ?? d
                            }
                            return Self.roundedHour(after: Date())
                        }()
                        insertEvent(title: title,
                                    start: start,
                                    end: start.addingTimeInterval(3600),
                                    recurrence: nil,
                                    category: pendingCategory,
                                    sourceText: "")
                    }
                    Task { await rescheduleNotifications() }
                }
                pendingTitle = nil
                pendingCategory = nil
                pendingKind = .task
            }
        }
    }

    /// Static helper used when the date prompt was dismissed without a
    /// chosen date for an event override: fall back to the next round
    /// hour from now.
    private static func roundedHour(after now: Date) -> Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day, .hour], from: now)
        comps.hour = (comps.hour ?? 0) + 1
        comps.minute = 0
        return Calendar.current.date(from: comps) ?? now.addingTimeInterval(3600)
    }

    private var inputRow: some View {
        HStack(spacing: 10) {
            HStack {
                TextField("Try \"Working Monday 7am to 3:30pm\" or \"Math homework due Friday\"",
                          text: $text)
                    .focused($focused)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.ink)
                    .submitLabel(.send)
                    .onSubmit { commit() }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Theme.surface2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(focused ? Theme.accent : Theme.border, lineWidth: 1)
            )
            .shadow(color: focused ? Theme.accentGlow : .clear,
                    radius: focused ? 6 : 0)

            Button(action: commit) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(text.isEmpty ? Theme.inkDim : Color.black)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(text.isEmpty ? Theme.surface3 : Theme.accent)
                    )
            }
            .buttonStyle(.plain)
            .disabled(text.isEmpty)
        }
    }

    // MARK: - Logic

    private func recomputePreview(_ new: String) {
        let trimmed = new.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { parsed = nil; return }
        let parserCats = categories.map { ParserCategory(id: $0.id, name: $0.name) }
        parsed = NLParser.parse(trimmed, categories: parserCats)
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let parserCats = categories.map { ParserCategory(id: $0.id, name: $0.name) }
        let result = NLParser.parse(trimmed, categories: parserCats)

        // Apply the user's type-override if they flipped Event/Task in the
        // preview.
        let finalKind: PreviewKind = {
            if let o = typeOverride { return o }
            switch result {
            case .event: return .event
            case .task:  return .task
            case .error: return .task
            }
        }()

        // Reset the input optimistically — user already pressed enter, so
        // the bar should clear immediately. The pending-task prompt (if
        // shown) carries the data forward.
        let originalText = text
        text = ""
        typeOverride = nil
        parsed = nil

        switch (finalKind, result) {
        case (.event, .event(let title, let s, let e, let recurrence, let cat)):
            insertEvent(title: title,
                        start: s, end: e,
                        recurrence: recurrence,
                        category: cat,
                        sourceText: originalText)
        case (.event, .task(let title, let due, let cat)):
            // User overrode Task → Event. If we have a due date, use it
            // as the start (1-hour duration). If we don't, ask the user
            // when it's happening — we shouldn't silently guess.
            if let s = due {
                insertEvent(title: title,
                            start: s,
                            end: s.addingTimeInterval(3600),
                            recurrence: nil,
                            category: cat,
                            sourceText: originalText)
            } else {
                pendingTitle = title
                pendingCategory = cat
                pendingKind = .event
                showDuePrompt = true
            }
        case (.task, .task(let title, let due, let cat)):
            if due == nil {
                // Ask the user when the task is due before saving.
                pendingTitle = title
                pendingCategory = cat
                pendingKind = .task
                showDuePrompt = true
            } else {
                insertTask(title: title, due: due, category: cat,
                           sourceText: originalText)
            }
        case (.task, .event(let title, let s, _, _, let cat)):
            // User overrode Event → Task. Use start as due.
            insertTask(title: title, due: s, category: cat,
                       sourceText: originalText)
        default:
            break
        }

        // Re-schedule notifications now that we've added something. (When
        // the due-date sheet is shown, we re-schedule again after the user
        // confirms, since that's the actual insert moment.)
        Task { await rescheduleNotifications() }
    }

    private func insertEvent(title: String,
                             start: Date,
                             end: Date,
                             recurrence: Recurrence?,
                             category: UUID?,
                             sourceText: String) {
        let event = Event(title: title,
                          startDate: start,
                          endDate: end,
                          categoryID: category,
                          recurrenceEnabled: recurrence != nil,
                          recurrenceByDay: recurrence?.byDay ?? [],
                          sourceText: sourceText)
        modelContext.insert(event)
        try? modelContext.save()
    }

    private func insertTask(title: String,
                            due: Date?,
                            category: UUID?,
                            sourceText: String = "") {
        let task = TaskItem(title: title,
                            dueDate: due,
                            categoryID: category,
                            sourceText: sourceText)
        modelContext.insert(task)
        try? modelContext.save()
    }

    private func rescheduleNotifications() async {
        let events = (try? modelContext.fetch(FetchDescriptor<Event>())) ?? []
        let tasks = (try? modelContext.fetch(FetchDescriptor<TaskItem>())) ?? []
        await NotificationScheduler.reschedule(events: events, tasks: tasks)
    }
}
