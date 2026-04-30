//
//  TaskDueDatePrompt.swift
//  MyPlanner
//
//  Sheet shown when the user commits a task without a date in their input.
//  Lets them pick a quick option (Today / Tomorrow / This weekend / Next
//  week) or set an exact date — or skip and save with no date.
//

import SwiftUI

struct TaskDueDatePrompt: View {
    let title: String
    let onCommit: (Date?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var customDate: Date = Calendar.current.date(byAdding: .day,
                                                                value: 1,
                                                                to: Date()) ?? Date()

    private let cal = Calendar.current

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                header
                quickOptions
                Divider().background(Theme.borderSoft)
                pickerSection
                Spacer()
                footer
            }
            .padding(Theme.Spacing.outer)
            .background(Theme.bg)
            .navigationTitle("When is this due?")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        // Pure cancel — do not save the task at all.
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 460)
        #endif
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.isEmpty ? "Untitled" : title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Pick a date or save without one.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkDim)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var quickOptions: some View {
        VStack(spacing: 8) {
            quickRow("Today",     subtitle: format(today),       date: today)
            quickRow("Tomorrow",  subtitle: format(tomorrow),    date: tomorrow)
            quickRow("This weekend", subtitle: format(thisWeekend), date: thisWeekend)
            quickRow("Next week", subtitle: format(nextWeek),    date: nextWeek)
        }
    }

    @ViewBuilder
    private func quickRow(_ label: String, subtitle: String, date: Date) -> some View {
        Button {
            onCommit(date)
            dismiss()
        } label: {
            HStack {
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(subtitle)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(Theme.inkDim)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.inkDim)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .fill(Theme.surface2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .stroke(Theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var pickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Or pick exactly")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.inkDim)
            DatePicker("", selection: $customDate)
                .datePickerStyle(.compact)
                .labelsHidden()
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                onCommit(nil)
                dismiss()
            } label: {
                Text("Save without date")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.card)
                            .fill(Theme.surface2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.card)
                            .stroke(Theme.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Button {
                onCommit(customDate)
                dismiss()
            } label: {
                Text("Save with date")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.card)
                            .fill(Theme.accent)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Quick option dates

    private var today: Date {
        // 9am today — gives the task a default time so reminder offsets
        // work, while still feeling like "today".
        applying(hour: 9, to: cal.startOfDay(for: Date()))
    }

    private var tomorrow: Date {
        applying(hour: 9, to: cal.date(byAdding: .day, value: 1,
                                       to: cal.startOfDay(for: Date())) ?? Date())
    }

    /// Next Saturday at 9am.
    private var thisWeekend: Date {
        let now = Date()
        let weekdayNow = cal.component(.weekday, from: now)   // 1=Sun…7=Sat
        let daysUntilSat = (7 - weekdayNow + 7) % 7   // 0..6, where 0 means today is Sat
        let offset = daysUntilSat == 0 ? 7 : daysUntilSat
        let target = cal.date(byAdding: .day, value: offset,
                              to: cal.startOfDay(for: now)) ?? now
        return applying(hour: 9, to: target)
    }

    /// Same weekday next week at 9am.
    private var nextWeek: Date {
        applying(hour: 9, to: cal.date(byAdding: .day, value: 7,
                                       to: cal.startOfDay(for: Date())) ?? Date())
    }

    private func applying(hour: Int, to date: Date) -> Date {
        var comps = cal.dateComponents([.year, .month, .day], from: date)
        comps.hour = hour
        comps.minute = 0
        return cal.date(from: comps) ?? date
    }

    private func format(_ d: Date) -> String {
        let f = DateFormatter()
        if cal.isDate(d, equalTo: Date(), toGranularity: .year) {
            f.dateFormat = "EEE, MMM d"
        } else {
            f.dateFormat = "EEE, MMM d, yyyy"
        }
        return f.string(from: d)
    }
}
