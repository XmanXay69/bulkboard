import AppKit
import BulkCore
import Foundation
import SwiftData

enum GroceryActions {
    static let weekKey = "groceryWeekStart"

    /// Rebuilds the list from a week's meal plan. Manual items stay; check marks carry over by name.
    static func generate(weekOf date: Date, context: ModelContext) {
        let start = date.weekStart
        let library = MealLibrary(context)
        let meals = MealPlanActions.entries(weekOf: start, context: context).compactMap(\.plannedMeal)
        let unitSystem = context.profile?.unitSystem ?? .imperial
        let sections = GroceryBuilder.build(GroceryBuilder.uses(meals: meals, templates: library.templates, foods: library.foods),
                                            unitSystem: unitSystem)

        let existing = context.fetchAll(GroceryItemRecord.self)
        let checked = Set(existing.filter(\.isChecked).map { $0.name.lowercased() })
        for item in existing where !item.isManual { context.delete(item) }

        var index = 0
        for section in sections {
            for line in section.lines {
                let item = GroceryItemRecord(name: line.name)
                item.amountText = line.amountText
                item.section = section.section
                item.isChecked = checked.contains(line.name.lowercased())
                item.sortIndex = index
                item.isDemo = context.profile?.isDemo ?? false
                context.insert(item)
                index += 1
            }
        }
        UserDefaults.standard.set(start.timeIntervalSince1970, forKey: weekKey)
        try? context.save()
    }

    static func addManual(name: String, amount: String, section: StoreSection, context: ModelContext) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let item = GroceryItemRecord(name: trimmed)
        item.amountText = amount.trimmingCharacters(in: .whitespaces)
        item.section = section
        item.isManual = true
        item.sortIndex = (context.fetchAll(GroceryItemRecord.self).map(\.sortIndex).max() ?? 0) + 1
        context.insert(item)
        try? context.save()
    }

    static func clearChecked(context: ModelContext) {
        for item in context.fetchAll(GroceryItemRecord.self) where item.isChecked { context.delete(item) }
        try? context.save()
    }

    static func uncheckAll(context: ModelContext) {
        for item in context.fetchAll(GroceryItemRecord.self) { item.isChecked = false }
        try? context.save()
    }

    static func grouped(_ items: [GroceryItemRecord]) -> [(section: StoreSection, items: [GroceryItemRecord])] {
        Dictionary(grouping: items, by: \.section)
            .map { section, items in
                (section, items.sorted { ($0.isChecked ? 1 : 0, $0.sortIndex, $0.name) < ($1.isChecked ? 1 : 0, $1.sortIndex, $1.name) })
            }
            .sorted { $0.section < $1.section }
    }

    static func plainText(_ items: [GroceryItemRecord], weekStart: Date?) -> String {
        let title = weekStart.map { "BulkBoard groceries · week of \($0.monthDay)" } ?? "BulkBoard groceries"
        return GroceryBuilder.plainText(title: title, sections: grouped(items).map { group in
            (group.section, group.items.map { ($0.name, $0.amountText, $0.isChecked) })
        })
    }

    static func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
