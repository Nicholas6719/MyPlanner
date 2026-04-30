//
//  WeekdayPicker.swift
//  MyPlanner
//
//  Multi-select S M T W T F S row used in the event editor for weekly
//  recurrence. Selected weekdays are stored as Int 0…6 (Sunday = 0).
//

import SwiftUI

struct WeekdayPicker: View {
    @Binding var selection: [Int]      // weekday numbers, 0=Sun … 6=Sat

    private let labels = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { day in
                let isOn = selection.contains(day)
                Button {
                    if isOn {
                        selection.removeAll { $0 == day }
                    } else {
                        selection.append(day)
                        selection.sort()
                    }
                } label: {
                    Text(labels[day])
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .foregroundStyle(isOn ? Color.black : Theme.inkSecondary)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isOn ? Theme.accent : Theme.surface2)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isOn ? Color.clear : Theme.border,
                                        lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
