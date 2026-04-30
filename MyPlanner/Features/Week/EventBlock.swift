//
//  EventBlock.swift
//  MyPlanner
//
//  Renders a single event instance as a colored block in the Week or Day
//  grid. Sized externally by the parent (caller computes geometry from
//  start/end dates and hour-row height); this view just renders.
//

import SwiftUI

struct EventBlock: View {
    let instance: EventInstance
    let category: PlannerCategory?
    let compact: Bool          // true = week view (smaller text), false = day view

    private var color: Color {
        if let category { return Color(hex: category.colorHex) }
        return Theme.accent
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // 3px solid accent bar on the left edge for recurring events.
            if instance.isRecurring {
                Rectangle()
                    .fill(color)
                    .frame(width: 3)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(instance.title.isEmpty ? "Untitled" : instance.title)
                    .font(.system(size: compact ? 11 : 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if !compact {
                    Text(timeRange)
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.85))
                    if instance.isRecurring {
                        Text("weekly")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.white.opacity(0.18)))
                    }
                } else {
                    Text(timeRange)
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(color.opacity(0.92))
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var timeRange: String {
        let f = DateFormatter()
        f.dateFormat = "h:mma"
        f.amSymbol = "am"
        f.pmSymbol = "pm"
        return "\(f.string(from: instance.start)) – \(f.string(from: instance.end))"
    }
}
