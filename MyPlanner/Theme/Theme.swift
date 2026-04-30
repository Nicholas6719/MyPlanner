//
//  Theme.swift
//  MyPlanner
//
//  Centralized color tokens, typography helpers, and shape constants.
//  All UI in the app should pull values from here so the look stays consistent
//  and so we can adjust the design from a single place.
//

import SwiftUI

// MARK: - Color Tokens
//
// We define every color the app uses as a static `Color` on the `Theme` enum.
// Hex literals are converted via `Color(hex:)` (defined below) so the values
// match the design spec exactly.

enum Theme {

    // Surfaces / backgrounds
    static let bg          = Color(hex: "#0a0a0b")
    static let surface     = Color(hex: "#131316")
    static let surface2    = Color(hex: "#1a1a1f")
    static let surface3    = Color(hex: "#232328")
    static let border      = Color(hex: "#2a2a31")
    static let borderSoft  = Color(hex: "#1f1f25")

    // Text
    static let ink          = Color(hex: "#f0f0f3")
    static let inkSecondary = Color(hex: "#c5c5cc")
    static let inkDim       = Color(hex: "#8e8e98")
    static let inkFaint     = Color(hex: "#5a5a64")

    // Accent (mint/teal)
    static let accent      = Color(hex: "#5eead4")
    static let accent2     = Color(hex: "#2dd4bf")
    static let accentSoft  = Color(red: 94/255, green: 234/255, blue: 212/255, opacity: 0.12)
    static let accentGlow  = Color(red: 94/255, green: 234/255, blue: 212/255, opacity: 0.25)

    // Status colors
    static let overdue     = Color(hex: "#f87171")
    static let overdueSoft = Color(red: 248/255, green: 113/255, blue: 113/255, opacity: 0.12)
    static let today       = Color(hex: "#fb923c")
    static let todaySoft   = Color(red: 251/255, green: 146/255, blue: 60/255, opacity: 0.12)
    static let soon        = Color(hex: "#fbbf24")
    static let soonSoft    = Color(red: 251/255, green: 191/255, blue: 36/255, opacity: 0.10)

    // Priority
    static let priorityHigh = Color(hex: "#f87171")
    static let priorityMed  = Color(hex: "#fbbf24")
    static let priorityLow  = Color(hex: "#94a3b8")

    /// Color used for events that don't have a category assigned. Visually
    /// distinct from any default category color (especially the mint
    /// `accent`, which the seeded "Work" category uses) so the user can
    /// tell at a glance that something is uncategorized rather than
    /// accidentally filed under Work.
    static let uncategorized = Color(hex: "#64748b")    // slate

    // Standard radii / spacing
    enum Radius {
        static let card: CGFloat   = 12
        static let chip: CGFloat   = 8
        static let sheet: CGFloat  = 18
    }

    enum Spacing {
        static let outer: CGFloat = 16
        static let inner: CGFloat = 12
        static let tight: CGFloat = 8
    }

    static let topbarHeight: CGFloat = 56
}

// MARK: - Hex Color Initializer
//
// Accepts strings like "#5eead4" or "5eead4". Falls back to magenta on
// anything malformed so the bug is impossible to miss visually.

extension Color {
    init(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt64(h, radix: 16) else {
            self = .pink   // obvious fallback
            return
        }
        let r = Double((v >> 16) & 0xff) / 255.0
        let g = Double((v >>  8) & 0xff) / 255.0
        let b = Double( v        & 0xff) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    /// Convert a SwiftUI Color back to a "#rrggbb" string. We use this when
    /// saving user-picked category colors to the database.
    func toHex() -> String {
        #if canImport(UIKit)
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        #else
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let r = ns.redComponent
        let g = ns.greenComponent
        let b = ns.blueComponent
        #endif
        return String(format: "#%02x%02x%02x",
                      Int(round(r * 255)),
                      Int(round(g * 255)),
                      Int(round(b * 255)))
    }
}

// MARK: - Typography Helpers
//
// Small extensions to apply our standard heading style with kerning.
// (We don't define custom fonts — system SF Pro is the right choice on Apple
// platforms.)

extension View {
    /// Tightens kerning slightly. Use on headings/titles.
    func headingKerning() -> some View {
        self.kerning(-0.3)
    }
}

// MARK: - Conditional View Modifier
//
// Tiny helper for "apply this modifier only on iOS / only on macOS".

extension View {
    @ViewBuilder
    func ifLet<T, Result: View>(_ value: T?,
                                transform: (Self, T) -> Result) -> some View {
        if let v = value {
            transform(self, v)
        } else {
            self
        }
    }
}
