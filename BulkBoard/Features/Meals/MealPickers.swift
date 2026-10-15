import BulkCore
import SwiftUI

/// Popover for choosing what goes in a slot: meals that fit the slot first, everything else on request, plus single foods.
struct MealPickerView: View {
    var slot: MealSlot
    var library: MealLibrary
    var onPick: (UUID?, UUID?) -> Void

    @State private var search = ""
    @State private var scope: Scope = .fits

    enum Scope: String, CaseIterable {
        case fits = "Fits slot"
        case allMeals = "All meals"
        case foods = "Foods"
    }

    private var recipes: [RecipeRecord] {
        library.recipes.values
            .filter { !$0.isArchived }
            .filter { scope != .fits || $0.slots.contains(slot) }
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
            .sorted { ($0.isFavorite ? 0 : 1, $0.name) < ($1.isFavorite ? 0 : 1, $1.name) }
    }

    private var foods: [FoodRecord] {
        library.foodRecords.values
            .filter { !$0.isArchived }
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: slot.symbol).foregroundStyle(Theme.hardwood)
                Text("Pick a \(slot.title.lowercased())").font(.system(size: 15, weight: .bold, design: .rounded))
            }
            TextField("Search", text: $search).textFieldStyle(.roundedBorder)
            Picker("Show", selection: $scope) {
                ForEach(Scope.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            List {
                if scope == .foods {
                    ForEach(foods) { food in
                        row(title: food.name, subtitle: food.servingLabel, macros: food.macros, badge: food.isAIEstimate) {
                            onPick(nil, food.id)
                        }
                    }
                } else {
                    ForEach(recipes) { recipe in
                        row(title: recipe.name, subtitle: recipe.slots.map(\.title).sorted().joined(separator: " · "),
                            macros: library.perServing(recipeID: recipe.id), badge: false, favorite: recipe.isFavorite) {
                            onPick(recipe.id, nil)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .frame(height: 320)
        }
        .padding(14)
        .frame(width: 340)
    }

    private func row(title: String, subtitle: String, macros: Macros, badge: Bool, favorite: Bool = false,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if favorite { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(Theme.scoreboard) }
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    if badge { AIEstimateBadge() }
                }
                HStack {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    Spacer()
                    MacroPill(macros: macros)
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Inspector panel with draggable meals.
struct MealLibraryPanel: View {
    var library: MealLibrary
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow("Drag into the week")
            TextField("Search meals", text: $search).textFieldStyle(.roundedBorder)
            List {
                ForEach(MealSlot.allCases, id: \.self) { slot in
                    let recipes = library.recipes.values
                        .filter { !$0.isArchived && $0.slots.contains(slot) }
                        .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
                        .sorted { $0.name < $1.name }
                    if !recipes.isEmpty {
                        Section(slot.title) {
                            ForEach(recipes) { recipe in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(recipe.name).font(.system(size: 12, weight: .semibold))
                                    MacroPill(macros: library.perServing(recipeID: recipe.id))
                                }
                                .padding(.vertical, 2)
                                .draggable(MealDragPayload.recipe(recipe.id)) {
                                    Label(recipe.name, systemImage: slot.symbol)
                                        .padding(8)
                                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .padding(12)
    }
}
