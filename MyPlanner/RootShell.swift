//
//  RootShell.swift
//  MyPlanner
//
//  Top-level layout: a custom topbar with the segmented Week/Day/Tasks
//  selector and a settings gear, then the active tab view, then the
//  composer pinned to the bottom.
//
//  We use one shell for both iOS and macOS rather than splitting into a
//  TabView/NavigationSplitView. The custom topbar gives us pixel-level
//  control over the visual style and avoids platform-specific quirks of
//  TabView (especially on macOS where TabView looks inconsistent with
//  the rest of the design).
//

import SwiftUI
import SwiftData

enum MainTab: String, CaseIterable, Identifiable {
    case week, day, tasks
    var id: String { rawValue }
    var label: String {
        switch self {
        case .week:  return "Week"
        case .day:   return "Day"
        case .tasks: return "Tasks"
        }
    }
}

struct RootShell: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var tab: MainTab = .week
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            topbar
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // The composer sits in a bottom safe-area inset so SwiftUI
        // automatically reserves space for it (no more overlap with the
        // bottom of Week/Day/Tasks content) and so it lifts above the
        // keyboard on iOS.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ComposerBar()
        }
        .background(Theme.bg.ignoresSafeArea())
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await rescheduleAll() } }
        }
        .task { await rescheduleAll() }
        #if os(macOS)
        .frame(minWidth: 900, minHeight: 600)
        #endif
    }

    // MARK: - Topbar

    private var topbar: some View {
        HStack(spacing: 12) {
            // Accent dot with soft glow + wordmark
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 8, height: 8)
                    Circle()
                        .fill(Theme.accent.opacity(0.4))
                        .frame(width: 22, height: 22)
                        .blur(radius: 8)
                        .allowsHitTesting(false)
                }
                Text("Planner")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .headingKerning()
            }

            Spacer()

            // Segmented tab selector
            HStack(spacing: 2) {
                ForEach(MainTab.allCases) { t in
                    Button {
                        tab = t
                    } label: {
                        Text(t.label)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(tab == t ? Color.black : Theme.inkSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(tab == t ? Theme.accent : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 9).fill(Theme.surface2))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.border, lineWidth: 1))

            Spacer()

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.surface2))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Spacing.outer)
        .frame(height: Theme.topbarHeight)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().fill(Theme.borderSoft).frame(height: 1), alignment: .bottom)
    }

    // MARK: - Tabbed content

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .week:  WeekView()
        case .day:   DayView()
        case .tasks: TasksView()
        }
    }

    private func rescheduleAll() async {
        let events = (try? modelContext.fetch(FetchDescriptor<Event>())) ?? []
        let tasks = (try? modelContext.fetch(FetchDescriptor<TaskItem>())) ?? []
        await NotificationScheduler.reschedule(events: events, tasks: tasks)
    }
}
