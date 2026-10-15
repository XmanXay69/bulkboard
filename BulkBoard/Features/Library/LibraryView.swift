import BulkCore
import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \RecipeRecord.name) private var recipes: [RecipeRecord]
    @Query(sort: \FoodRecord.name) private var foods: [FoodRecord]

    @State private var tab: Tab = .meals
    @State private var search = ""
    @State private var foodFilter: FoodFilter = .all
    @State private var editingRecipe: RecipeRecord?
    @State private var editingFood: FoodRecord?
    @State private var selectedFoods = Set<FoodRecord.ID>()

    enum Tab: String, CaseIterable { case meals = "Meals & Shakes", foods = "Foods" }
    enum FoodFilter: String, CaseIterable { case all = "All", mine = "My foods", builtIn = "Built-in" }

    private var library: MealLibrary { MealLibrary(foods: foods, recipes: recipes) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Foods & Recipes", subtitle: "Built-in foods, your own foods, meals and shakes") {
                HStack(spacing: 8) {
                    if tab == .meals {
                        Button { newRecipe(shake: true) } label: { Label("New shake", systemImage: "cup.and.saucer.fill") }
                            .buttonStyle(.bordered).controlSize(.small)
                        Button { newRecipe(shake: false) } label: { Label("New meal", systemImage: "plus") }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                    } else {
                        Button { newFood() } label: { Label("New food", systemImage: "plus") }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                            .keyboardShortcut("n", modifiers: [.command, .shift])
                    }
                }
            }
            HStack {
                Picker("View", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
                .labelsHidden()
                if tab == .foods {
                    Picker("Filter", selection: $foodFilter) {
                        ForEach(FoodFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                    .labelsHidden()
                }
                Spacer()
                TextField("Search", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
            }
            switch tab {
            case .meals: mealsGrid
            case .foods: foodsTable
            }
        }
        .padding(24)
        .sheet(item: $editingRecipe) { recipe in
            RecipeEditor(recipe: recipe, library: library)
        }
        .sheet(item: $editingFood) { food in
            FoodEditor(food: food)
        }
    }

    // MARK: Meals

    private var visibleRecipes: [RecipeRecord] {
        recipes.filter { !$0.isArchived && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }
            .sorted { ($0.isFavorite ? 0 : 1, $0.isShake ? 1 : 0, $0.name) < ($1.isFavorite ? 0 : 1, $1.isShake ? 1 : 0, $1.name) }
    }

    private var mealsGrid: some View {
        let library = library
        return ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 12) {
                ForEach(visibleRecipes) { recipe in
                    RecipeCard(recipe: recipe, macros: library.perServing(recipeID: recipe.id))
                        .onTapGesture { editingRecipe = recipe }
                        .contextMenu {
                            Button(recipe.isFavorite ? "Unfavorite" : "Favorite", systemImage: "star") {
                                recipe.isFavorite.toggle()
                            }
                            Button("Duplicate", systemImage: "plus.square.on.square") { duplicate(recipe) }
                            Divider()
                            Button("Delete", systemImage: "trash", role: .destructive) { delete(recipe) }
                        }
                }
            }
        }
    }

    // MARK: Foods

    private var visibleFoods: [FoodRecord] {
        foods.filter { food in
            guard !food.isArchived else { return false }
            switch foodFilter {
            case .all: break
            case .mine: if food.isBuiltIn { return false }
            case .builtIn: if !food.isBuiltIn { return false }
            }
            return search.isEmpty || food.name.localizedCaseInsensitiveContains(search)
        }
    }

    private var foodsTable: some View {
        Table(visibleFoods, selection: $selectedFoods) {
            TableColumn("Food") { food in
                HStack(spacing: 6) {
                    Text(food.name).fontWeight(.semibold)
                    if !food.isBuiltIn { Text("MINE").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.accent) }
                    if food.isAIEstimate { AIEstimateBadge() }
                    if food.shakerSafe { Image(systemName: "cup.and.saucer.fill").font(.system(size: 10)).foregroundStyle(Theme.accent).help("Shaker-safe") }
                }
            }
            .width(min: 220, ideal: 280)
            TableColumn("Serving") { Text($0.servingLabel).foregroundStyle(Theme.textSecondary) }
                .width(min: 120, ideal: 170)
            TableColumn("kcal") { Text(Fmt.int($0.kcal)).monospacedDigit().foregroundStyle(Theme.textPrimary) }.width(56)
            TableColumn("P") { Text(Fmt.number($0.protein)).monospacedDigit().foregroundStyle(Theme.textPrimary) }.width(48)
            TableColumn("C") { Text(Fmt.number($0.carbs)).monospacedDigit().foregroundStyle(Theme.textPrimary) }.width(48)
            TableColumn("F") { Text(Fmt.number($0.fat)).monospacedDigit().foregroundStyle(Theme.textPrimary) }.width(48)
            TableColumn("Aisle") { Text($0.section.title).foregroundStyle(Theme.textSecondary) }.width(min: 90, ideal: 110)
        }
        .contextMenu(forSelectionType: FoodRecord.ID.self) { ids in
            if let id = ids.first, let food = foods.first(where: { $0.id == id }) {
                Button("Edit", systemImage: "pencil") { editingFood = food }
                Button("Delete", systemImage: "trash", role: .destructive) { delete(food) }
            }
        } primaryAction: { ids in
            if let id = ids.first { editingFood = foods.first { $0.id == id } }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Actions

    private func newRecipe(shake: Bool) {
        let recipe = RecipeRecord(name: shake ? "New Shake" : "New Meal")
        recipe.isShake = shake
        recipe.slots = shake ? [.shake] : [.lunch, .dinner]
        context.insert(recipe)
        editingRecipe = recipe
    }

    private func duplicate(_ recipe: RecipeRecord) {
        let copy = RecipeRecord(name: "\(recipe.name) (copy)")
        copy.slotsRaw = recipe.slotsRaw
        copy.ingredientsData = recipe.ingredientsData
        copy.isShake = recipe.isShake
        context.insert(copy)
        editingRecipe = copy
    }

    private func delete(_ recipe: RecipeRecord) {
        // Built-ins are archived so the seeder doesn't bring them back.
        if recipe.seedKey != nil { recipe.isArchived = true } else { context.delete(recipe) }
        try? context.save()
    }

    private func newFood() {
        let food = FoodRecord(name: "")
        food.servingLabel = "1 serving"
        context.insert(food)
        editingFood = food
    }

    private func delete(_ food: FoodRecord) {
        if food.seedKey != nil { food.isArchived = true } else { context.delete(food) }
        try? context.save()
    }
}

struct RecipeCard: View {
    var recipe: RecipeRecord
    var macros: Macros

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: recipe.isShake ? "cup.and.saucer.fill" : "fork.knife")
                    .foregroundStyle(recipe.isShake ? Theme.accent : Theme.accent)
                Text(recipe.name).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer()
                if recipe.isFavorite { Image(systemName: "star.fill").foregroundStyle(Theme.textPrimary) }
            }
            HStack(spacing: 4) {
                ForEach(MealSlot.allCases.filter(recipe.slots.contains), id: \.self) { slot in
                    Text(slot.title)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.surfaceRaised, in: Capsule())
                        .foregroundStyle(Theme.textSecondary)
                }
                if recipe.isShake {
                    Text("Shaker-safe").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.accent)
                }
            }
            MacroPill(macros: macros)
        }
        .card(padding: 14)
        .contentShape(Rectangle())
    }
}
