import BulkCore
import SwiftData
import SwiftUI

/// Create or edit a food. New foods that are left blank get discarded on cancel.
struct FoodEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var food: FoodRecord
    @State private var showAI = false

    private var isValid: Bool { !food.name.trimmingCharacters(in: .whitespaces).isEmpty && food.servingAmount > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(food.name.isEmpty ? "New food" : food.name).font(.system(size: 22, weight: .semibold))
                if food.isAIEstimate { AIEstimateBadge() }
                Spacer()
                if food.isBuiltIn { Text("Built-in").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textSecondary) }
            }
            Form {
                Section("Food") {
                    TextField("Name", text: $food.name)
                    TextField("Brand (optional)", text: Binding(get: { food.brand ?? "" }, set: { food.brand = $0.isEmpty ? nil : $0 }))
                    TextField("Serving description", text: $food.servingLabel, prompt: Text("e.g. 1 scoop (33 g)"))
                    LabeledContent("Amount per serving") {
                        HStack {
                            TextField("Amount", value: $food.servingAmount, format: .number)
                                .frame(width: 70).multilineTextAlignment(.trailing).labelsHidden()
                            Picker("Unit", selection: $food.servingUnitRaw) {
                                ForEach(GroceryUnit.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
                            }
                            .labelsHidden().frame(width: 100)
                        }
                    }
                    Picker("Store section", selection: $food.sectionRaw) {
                        ForEach(StoreSection.allCases, id: \.self) { Label($0.title, systemImage: $0.symbol).tag($0.rawValue) }
                    }
                }
                Section {
                    NumberField(label: "Calories", value: $food.kcal, unit: "kcal", decimals: 0)
                    NumberField(label: "Protein", value: $food.protein, unit: "g")
                    NumberField(label: "Carbs", value: $food.carbs, unit: "g")
                    NumberField(label: "Fat", value: $food.fat, unit: "g")
                    HStack {
                        Text("Macros imply \(Fmt.int(food.macros.kcalFromMacros)) kcal").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Button("Use that") { food.kcal = food.macros.kcalFromMacros.rounded() }.controlSize(.small)
                    }
                } header: {
                    Text("Per serving")
                }
                Section("Details") {
                    Toggle("Mixes in a shaker bottle (no blender)", isOn: $food.shakerSafe)
                    FlowLayout(spacing: 6) {
                        ForEach(Allergen.allCases, id: \.self) { allergen in
                            Chip(title: allergen.title, isOn: food.allergens.contains(allergen)) {
                                if food.allergens.contains(allergen) { food.allergens.remove(allergen) } else { food.allergens.insert(allergen) }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                if OllamaClient.shared.isAvailable {
                    Button { showAI = true } label: { Label("Estimate with AI", systemImage: "sparkles") }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(food.name.isEmpty)
                }
                Spacer()
                Button("Cancel") { cancel() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding(24)
        .frame(width: 520, height: 680)
        .sheet(isPresented: $showAI) {
            AIEstimateSheet(query: "\(food.name) — \(food.servingLabel)") { estimate in
                food.macros = estimate.macros
                if food.servingLabel == "1 serving" { food.servingLabel = estimate.serving }
                food.isAIEstimate = true
            }
        }
    }

    private func save() {
        food.name = food.name.trimmingCharacters(in: .whitespaces)
        try? context.save()
        dismiss()
    }

    private func cancel() {
        if food.name.isEmpty { context.delete(food) } else { context.rollback() }
        dismiss()
    }
}

/// Build a meal or shake from foods. Shakes only offer shaker-safe ingredients.
struct RecipeEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var recipe: RecipeRecord
    var library: MealLibrary

    @State private var ingredients: [Ingredient] = []
    @State private var showAdd = false

    private var totals: Macros {
        ingredients.map { (library.foods[$0.foodID]?.macros ?? .zero) * $0.servings }.sum()
    }

    private var unsafeForShaker: [String] {
        guard recipe.isShake else { return [] }
        return ingredients.compactMap { library.foodRecords[$0.foodID] }.filter { !$0.shakerSafe }.map(\.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: recipe.isShake ? "cup.and.saucer.fill" : "fork.knife")
                    .font(.system(size: 20)).foregroundStyle(recipe.isShake ? Theme.accent : Theme.accent)
                TextField("Name", text: $recipe.name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .semibold))
            }
            MacroSummary(macros: totals, size: 26)
            HStack(spacing: 6) {
                ForEach(MealSlot.allCases, id: \.self) { slot in
                    let on = recipe.slots.contains(slot)
                    Button {
                        var slots = recipe.slots
                        if on { slots.remove(slot) } else { slots.insert(slot) }
                        recipe.slots = slots
                    } label: {
                        Label(slot.title, systemImage: slot.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .foregroundStyle(on ? .white : Theme.textPrimary)
                            .background(on ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.surfaceRaised), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Toggle("Shake", isOn: $recipe.isShake).toggleStyle(.switch).controlSize(.small)
            }
            if !unsafeForShaker.isEmpty {
                WarningBanner(message: "Won't mix in a shaker bottle: \(unsafeForShaker.joined(separator: ", ")). Swap for a powder or liquid.", serious: true)
            }
            SectionLabel("Ingredients")
            List {
                ForEach(Array(ingredients.enumerated()), id: \.offset) { index, ingredient in
                    if let food = library.foodRecords[ingredient.foodID] {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(food.name).font(.system(size: 13, weight: .semibold))
                                Text(food.servingLabel).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            MacroPill(macros: food.macros * ingredient.servings)
                            TextField("Servings", value: $ingredients[index].servings, format: .number.precision(.fractionLength(0...2)))
                                .frame(width: 54).multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder)
                            Text("×").foregroundStyle(Theme.textSecondary)
                            Button { ingredients.remove(at: index) } label: { Image(systemName: "minus.circle.fill") }
                                .buttonStyle(.plain).foregroundStyle(Theme.negative)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .frame(minHeight: 200)
            HStack {
                Button { showAdd = true } label: { Label("Add ingredient", systemImage: "plus") }
                    .buttonStyle(.bordered).controlSize(.small)
                    .popover(isPresented: $showAdd) {
                        FoodSearchPicker(library: library, shakerOnly: recipe.isShake) { foodID in
                            ingredients.append(Ingredient(foodID: foodID, servings: 1))
                            showAdd = false
                        }
                    }
                Spacer()
                Button("Cancel") {
                    if recipe.ingredients.isEmpty && ingredients.isEmpty { context.delete(recipe) } else { context.rollback() }
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Save") {
                    recipe.ingredients = ingredients.filter { $0.servings > 0 }
                    if recipe.slots.isEmpty { recipe.slots = recipe.isShake ? [.shake] : [.lunch] }
                    try? context.save()
                    dismiss()
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
                .keyboardShortcut(.defaultAction)
                .disabled(recipe.name.trimmingCharacters(in: .whitespaces).isEmpty || ingredients.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 640, height: 640)
        .onAppear { ingredients = recipe.ingredients }
    }
}

struct FoodSearchPicker: View {
    var library: MealLibrary
    var shakerOnly: Bool
    var onPick: (UUID) -> Void
    @State private var search = ""

    private var foods: [FoodRecord] {
        library.foodRecords.values
            .filter { !$0.isArchived && (!shakerOnly || $0.shakerSafe) }
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
            .sorted { ($0.isBuiltIn ? 1 : 0, $0.name) < ($1.isBuiltIn ? 1 : 0, $1.name) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search foods", text: $search).textFieldStyle(.roundedBorder)
            if shakerOnly {
                Text("Shaker-safe only: powders and liquids.").font(.system(size: 11)).foregroundStyle(Theme.accent)
            }
            List(foods) { food in
                Button { onPick(food.id) } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(food.name).font(.system(size: 12, weight: .semibold))
                            Text(food.servingLabel).font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        MacroPill(macros: food.macros)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .frame(height: 300)
        }
        .padding(12)
        .frame(width: 380)
    }
}
