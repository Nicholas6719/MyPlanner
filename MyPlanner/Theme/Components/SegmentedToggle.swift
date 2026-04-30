//
//  SegmentedToggle.swift
//  MyPlanner
//
//  A simple segmented-control-like component used for things like
//  Event/Task type override and Priority Low/Med/High. Built from scratch
//  so we can style it consistently with the rest of the app.
//

import SwiftUI

struct SegmentedToggle<Value: Hashable>: View {
    let options: [(label: String, value: Value)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { opt in
                Button {
                    selection = opt.value
                } label: {
                    Text(opt.label)
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .foregroundStyle(selection == opt.value
                                         ? Color.black
                                         : Theme.inkSecondary)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selection == opt.value
                                      ? Theme.accent
                                      : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Theme.surface2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Theme.border, lineWidth: 1)
        )
    }
}
