//
//  Category.swift
//  MyPlanner
//
//  Color-coded grouping that events and tasks can be tagged with.
//
//  NOTE: We named the type `PlannerCategory` instead of `Category` because
//  the Objective-C runtime exposes a typealias `Category = OpaquePointer`
//  from <objc/runtime.h>, which would silently shadow our model in some
//  contexts and produce maddening "no member 'name'" errors. Adding a
//  prefix avoids the collision entirely.
//

import Foundation
import SwiftData

@Model
final class PlannerCategory {
    var id: UUID = UUID()
    var name: String = ""
    /// "#rrggbb" hex string, parsed by `Color(hex:)`.
    var colorHex: String = "#5eead4"
    var createdAt: Date = Date()

    init(id: UUID = UUID(),
         name: String = "",
         colorHex: String = "#5eead4",
         createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
    }
}
