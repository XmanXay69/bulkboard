import BulkCore
import SwiftData
import SwiftUI

/// Log what you ate: an optional photo, then each item with its brand, product and amount,
/// matched to exact label numbers online or in your food list.
struct LogMealSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var appModel
    @Bindable var draft: MealDraft
    @Query private var foods: [FoodRecord]
    @Query private var recipes: [RecipeRecord]
    @State private var error: String?
    @State private var recipeSearch = ""

    private var library: MealLibrary { MealLibrary(foods: foods, recipes: recipes) }
    private var ai: OllamaClient { OllamaClient.shared }

    var body: some View {
        let library = library
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            HStack(alignment: .top, spacing: 20) {
                details(library: library)
                    .frame(width: 250)
                Divider()
                ScrollView {
                    Group {
                        if draft.mode == .build || draft.isEditing {
                            itemsList(library: library)
                        } else {
                            savedMeals(library: library)
                        }
                    }
                    .padding(.vertical, 2)
                    .padding(.trailing, 4)
                }
            }
            .padding(20)
            Divider()
            footer(library: library)
        }
        .frame(width: 940, height: 680)
        .task(id: draft.photo) { await ItemLookup.scanBarcodes(draft) }
    }

    // MARK: Header & details

    private var header: some View {
        HStack {
            Text(draft.isEditing ? "Edit meal" : "Log a meal").font(.system(size: 20, weight: .semibold))
            Spacer()
            if !draft.isEditing {
                Picker("Mode", selection: $draft.mode) {
                    ForEach(MealDraft.Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 260)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func details(library: MealLibrary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            PhotoInput(photo: $draft.photo, height: 190, prompt: "Add a photo of the meal (optional). It's kept on this Mac.")
            if draft.photo != nil, draft.mode == .build {
                photoTools(library: library)
            }
            VStack(alignment: .leading, spacing: 10) {
                if draft.mode == .build || draft.isEditing {
                    TextField(draft.placeholderName == "Meal" ? "Name (optional)" : draft.placeholderName, text: $draft.name)
                        .textFieldStyle(.roundedBorder)
                }
                DatePicker("Day", selection: $draft.day, displayedComponents: .date)
                Picker("Meal", selection: $draft.slot) {
                    ForEach(MealSlot.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                TextField("Notes (optional)", text: $draft.notes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
            }
            .font(.system(size: 13))
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func photoTools(library: MealLibrary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(draft.barcodes, id: \.self) { code in
                Button { Task { await ItemLookup.lookUpBarcode(code, in: draft, library: library) } } label: {
                    Label("Look up barcode \(code)", systemImage: "barcode.viewfinder")
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
            if ai.canSeeImages {
                HStack(spacing: 6) {
                    Button { Task { await ItemLookup.fillFromPhoto(draft, library: library) } } label: {
                        Label("Fill in from photo", systemImage: "sparkles")
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(draft.isReadingPhoto)
                    .help("A model on this Mac lists what it sees. You confirm each item.")
                    if draft.isReadingPhoto { ProgressView().controlSize(.small) }
                }
            }
            if let message = draft.photoMessage {
                Text(message).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Items

    private func itemsList(library: MealLibrary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("What's in it?").font(.system(size: 15, weight: .semibold))
                Text("Type each thing, its brand if it has one, and how much. Look up finds the exact label numbers in your food list and on Open Food Facts.")
                    .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(draft.items) { item in
                ItemRow(item: item, library: library, canRemove: draft.items.count > 1) {
                    draft.items.removeAll { $0.id == item.id }
                }
            }
            Button {
                draft.items.append(ItemDraft())
            } label: { Label("Add another item", systemImage: "plus") }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .padding(.top, 2)
        }
    }

    // MARK: Saved meals

    private func savedMeals(library: MealLibrary) -> some View {
        let all = library.recipes.values.filter { !$0.isArchived }
            .filter { recipeSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(recipeSearch) }
            .sorted { ($0.isBuiltIn ? 1 : 0, $0.isFavorite ? 0 : 1, $0.name) < ($1.isBuiltIn ? 1 : 0, $1.isFavorite ? 0 : 1, $1.name) }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Log a meal you've saved, or one from the meal list.").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            TextField("Search meals", text: $recipeSearch).textFieldStyle(.roundedBorder)
            ForEach(all) { recipe in
                let selected = draft.recipeID == recipe.id
                Button {
                    draft.recipeID = recipe.id
                    if let slot = recipe.slots.first, !recipe.slots.contains(draft.slot) { draft.slot = slot }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(selected ? Theme.accent : Theme.textSecondary)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(recipe.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                                if !recipe.isBuiltIn { Text("Yours").font(.system(size: 10)).foregroundStyle(Theme.textSecondary) }
                            }
                            Text(recipe.slots.map(\.title).sorted().joined(separator: " · "))
                                .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        MacroPill(macros: library.perServing(recipeID: recipe.id))
                    }
                    .padding(8)
                    .background(selected ? Theme.accent.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Footer

    private func footer(library: MealLibrary) -> some View {
        let savedMode = draft.mode == .saved && !draft.isEditing
        let totals = savedMode ? (draft.recipeID.map { library.perServing(recipeID: $0) * draft.recipeServings } ?? .zero) : draft.totals
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Fmt.int(totals.kcal)) kcal").font(.stat(20)).foregroundStyle(Theme.textPrimary).contentTransition(.numericText())
                Text("\(Fmt.int(totals.protein)) g protein · \(Fmt.int(totals.carbs)) g carbs · \(Fmt.int(totals.fat)) g fat")
                    .font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.textSecondary)
            }
            if savedMode {
                Stepper("×\(Fmt.number(draft.recipeServings, maxDecimals: 2)) servings", value: $draft.recipeServings, in: 0.25...6, step: 0.25)
                    .font(.system(size: 13))
            } else if draft.pendingCount > 0 {
                Label("\(draft.pendingCount) item\(draft.pendingCount == 1 ? "" : "s") not looked up yet", systemImage: "exclamationmark.circle")
                    .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(Theme.negative).lineLimit(2) }
            Spacer()
            if !savedMode && !draft.isEditing {
                Toggle("Save as a meal I can reuse", isOn: $draft.saveAsMeal)
                    .toggleStyle(.checkbox).font(.system(size: 12))
            }
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button(draft.isEditing ? "Save" : "Log meal") { save(library: library, totals: totals) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(savedMode ? draft.recipeID == nil : draft.readyItems.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func save(library: MealLibrary, totals: Macros) {
        do {
            if let record = draft.editing {
                try MealLogActions.update(record, name: draft.name, items: draft.readyItems, slot: draft.slot, day: draft.day,
                                          photo: draft.photoChange, notes: draft.notes, context: context)
            } else if draft.mode == .saved, let id = draft.recipeID, let recipe = library.recipes[id] {
                let record = try MealLogActions.log(recipe: recipe, servings: draft.recipeServings, slot: draft.slot, day: draft.day,
                                                    photo: draft.photo, library: library, context: context)
                record.notes = draft.notes
                try? context.save()
            } else {
                var recipeID: UUID?
                if draft.saveAsMeal {
                    recipeID = MealLogActions.saveAsMeal(name: draft.name, items: draft.readyItems, slot: draft.slot, context: context).id
                }
                try MealLogActions.log(name: draft.name, items: draft.readyItems, slot: draft.slot, day: draft.day,
                                       photo: draft.photo, notes: draft.notes, recipeID: recipeID, context: context)
            }
            appModel.celebrate(.dayComplete, title: draft.isEditing ? "Meal updated" : "Meal logged",
                               detail: "\(draft.slot.title) · \(Fmt.int(totals.kcal)) kcal · \(Fmt.int(totals.protein)) g protein")
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Item row

struct ItemRow: View {
    @Bindable var item: ItemDraft
    var library: MealLibrary
    var canRemove: Bool
    var onRemove: () -> Void
    @FocusState private var focused: Bool

    private var ai: OllamaClient { OllamaClient.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                TextField("What is it? e.g. pepperoni pizza, or a barcode", text: $item.product)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit(lookUp)
                TextField("Brand", text: $item.brand)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                    .onSubmit(lookUp)
                Button(action: lookUp) { Label("Look up", systemImage: "magnifyingglass") }
                    .buttonStyle(.bordered).controlSize(.regular)
                    .disabled(item.isBlank || item.isBusy)
                if canRemove {
                    Button(action: onRemove) { Image(systemName: "xmark") }
                        .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
                        .help("Remove item")
                }
            }
            HStack(spacing: 8) {
                Text("How much").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                TextField("Amount", value: $item.quantity, format: .number.precision(.fractionLength(0...2)))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                Picker("Unit", selection: $item.unit) {
                    ForEach(item.unitChoices, id: \.self) { unit in Text(item.unitTitle(unit)).tag(unit) }
                }
                .labelsHidden()
                .frame(maxWidth: 260)
                Spacer(minLength: 8)
                if let macros = item.macros {
                    MacroPill(macros: macros)
                } else if item.isBusy {
                    ProgressView().controlSize(.small)
                }
            }
            if item.fromPhoto && item.match == nil {
                Label("Guessed from the photo", systemImage: "sparkles").font(.system(size: 11)).foregroundStyle(Theme.accent)
            }
            if let match = item.match {
                matchLine(match)
            }
            if let note = item.unitNote {
                Text(note).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            status
            if item.match == nil && !item.results.isEmpty { results }
            if item.match == nil && (!item.results.isEmpty || isFailed) { fallbacks }
            if item.showManual { manualEntry }
        }
        .padding(12)
        .background(Theme.surfaceRaised.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onAppear { if item.isBlank && item.match == nil { focused = true } }
    }

    private var isFailed: Bool { if case .failed = item.state { true } else { false } }

    private func lookUp() {
        guard !item.isBlank, !item.isBusy else { return }
        Task { await ItemLookup.search(item, library: library) }
    }

    private func matchLine(_ match: ItemMatch) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: match.source.isEstimate ? "sparkles" : "checkmark.circle.fill")
                .foregroundStyle(match.source.isEstimate ? Theme.accent : Theme.positive)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text([match.brand, match.name].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    if match.source.isEstimate { AIEstimateBadge() }
                }
                Text(match.detail).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).lineLimit(2)
                if case .openFoodFacts = match.source, let check = match.labelCheck {
                    Text("Label check: \(check). Doesn't match your package? Hit Change.")
                        .font(.system(size: 11)).foregroundStyle(Theme.textSecondary).lineLimit(2)
                }
            }
            Spacer()
            Button("Change") {
                item.match = nil
                item.unitNote = nil
                lookUp()
            }
            .buttonStyle(.link).font(.system(size: 12))
        }
    }

    @ViewBuilder
    private var status: some View {
        switch item.state {
        case .searching:
            Text(NutritionLookup.shared.isEnabled ? "Searching your foods and Open Food Facts…" : "Searching your foods…")
                .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
        case .loadingDetails:
            Text("Getting the label…").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
        case .estimating:
            Text("Estimating with \(ai.model)…").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
        case let .failed(message):
            Text(message).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
        case .idle:
            if let note = item.onlineNote, item.match == nil {
                Text(note).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(item.results) { candidate in
                Button { Task { await ItemLookup.choose(candidate, for: item, library: library) } } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(candidate.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                            Text([candidate.subtitle, candidate.badge].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.system(size: 11)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                        }
                        Spacer()
                        Text(candidate.energyText).font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.textSecondary)
                        Text("Use").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 7))
            }
        }
    }

    private var fallbacks: some View {
        HStack(spacing: 12) {
            Text("Not it?").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            if ai.isAvailable {
                Button("Estimate with AI") { Task { await ItemLookup.estimate(item) } }
            }
            Button("Enter the numbers") { item.showManual.toggle() }
            Button("Search the web") { NutritionLookup.searchWeb(product: item.product, brand: item.brand) }
        }
        .buttonStyle(.link)
        .font(.system(size: 12))
    }

    private var manualEntry: some View {
        HStack(spacing: 8) {
            Text("For \(Fmt.number(item.quantity, maxDecimals: 2)) \(item.unit.label(quantity: item.quantity, liquid: false)):")
                .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            manualField("kcal", \.kcal)
            manualField("protein g", \.protein)
            manualField("carbs g", \.carbs)
            manualField("fat g", \.fat)
            Button("Use") { item.applyManual() }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(item.manual.kcal <= 0 && item.manual.protein <= 0)
        }
    }

    private func manualField(_ label: String, _ keyPath: WritableKeyPath<Macros, Double>) -> some View {
        TextField(label, value: Binding(get: { item.manual[keyPath: keyPath] }, set: { item.manual[keyPath: keyPath] = $0 }),
                  format: .number.precision(.fractionLength(0...1)))
            .textFieldStyle(.roundedBorder)
            .frame(width: 74)
            .help(label)
    }
}
