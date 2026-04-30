//
//  Chip.swift
//  MyPlanner
//
//  A small pill-shaped button used in filter rows and tag-like UI.
//

import SwiftUI

struct Chip: View {
    let title: String
    let count: Int?          // optional count badge
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(isSelected
                                           ? Color.black.opacity(0.25)
                                           : Theme.surface3)
                        )
                }
            }
            .foregroundStyle(isSelected ? Color.black : Theme.inkSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.chip)
                    .fill(isSelected ? Theme.accent : Theme.surface2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.chip)
                    .stroke(isSelected ? Color.clear : Theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
