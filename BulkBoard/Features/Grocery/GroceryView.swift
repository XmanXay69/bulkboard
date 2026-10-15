import BulkCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct GroceryView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \GroceryItemRecord.sortIndex) private var items: [GroceryItemRecord]
    @AppStorage(GroceryActions.weekKey) private var weekStamp: Double = 0
    @State private var exporting = false
    @State private var copied = false

    private var weekStart: Date? { weekStamp > 0 ? Date(timeIntervalSince1970: weekStamp) : nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(eyebrow: "Grocery List", title: weekStart.map { "Week of \($0.monthDay)" } ?? "Groceries") {
                    HStack(spacing: 8) {
                        Menu {
                            Button("This week") { generate(Date.now) }
                            Button("Next week") { generate(Date.now.adding(days: 7)) }
                            Button("Week shown in Meal Plan") { generate(appModel.planWeekStart) }
                        } label: {
                            Label("Generate from plan", systemImage: "wand.and.stars")
                        } primaryAction: {
                            generate(appModel.planWeekStart)
                        }
                        .menuStyle(.button)
                        .fixedSize()
                        .help("Build the list from the meal plan (⇧⌘G)")
                        Button { openWindow(id: "grocery") } label: { Label("Pop out", systemImage: "iphone") }
                            .buttonStyle(GhostButtonStyle(compact: true))
                            .help("Phone-sized check-off window")
                    }
                }

                if items.isEmpty {
                    EmptyStateView(symbol: "cart", title: "No list yet",
                                   message: "Plan your week, then build the list in one tap. Quantities merge across meals and group by aisle.",
                                   actionTitle: "Generate from this week") { generate(appModel.planWeekStart) }
                        .card()
                } else {
                    HStack(spacing: 10) {
                        progress
                        Spacer()
                        Button { copy() } label: { Label(copied ? "Copied" : "Copy as text", systemImage: copied ? "checkmark" : "doc.on.doc") }
                            .buttonStyle(GhostButtonStyle(compact: true))
                            .keyboardShortcut("c", modifiers: [.command, .shift])
                        Button { exporting = true } label: { Label("Export .txt", systemImage: "square.and.arrow.up") }
                            .buttonStyle(GhostButtonStyle(compact: true))
                        Menu {
                            Button("Uncheck all") { GroceryActions.uncheckAll(context: context) }
                            Button("Remove checked items", role: .destructive) { GroceryActions.clearChecked(context: context) }
                        } label: { Image(systemName: "ellipsis.circle") }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                    }
                    GroceryListContent(items: items, compact: false)
                }
            }
            .padding(24)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .onAppear(perform: handleRequest)
        .onChange(of: appModel.groceryRequest) { handleRequest() }
        .fileExporter(isPresented: $exporting, document: PlainTextDocument(text: GroceryActions.plainText(items, weekStart: weekStart)),
                      contentType: .plainText, defaultFilename: "BulkBoard Groceries.txt") { _ in }
    }

    private var progress: some View {
        let done = items.filter(\.isChecked).count
        return HStack(spacing: 12) {
            ScoreboardStat(value: "\(done)/\(items.count)", label: "In the cart", color: done == items.count ? Theme.net : Theme.scoreboard, size: 22)
            XPBar(progress: items.isEmpty ? 0 : Double(done) / Double(items.count), height: 10, color: Theme.net)
                .frame(width: 180)
        }
    }

    private func handleRequest() {
        guard let week = appModel.groceryRequest else { return }
        appModel.groceryRequest = nil
        generate(week)
    }

    private func generate(_ week: Date) {
        withAnimation(.spring) { GroceryActions.generate(weekOf: week, context: context) }
    }

    private func copy() {
        GroceryActions.copyToClipboard(GroceryActions.plainText(items, weekStart: weekStart))
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

/// The list itself: add row plus aisle sections. Shared with the pop-out window.
struct GroceryListContent: View {
    @Environment(\.modelContext) private var context
    var items: [GroceryItemRecord]
    var compact: Bool

    @State private var newName = ""
    @State private var newAmount = ""
    @State private var newSection: StoreSection = .other
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 16) {
            addRow
            ForEach(GroceryActions.grouped(items), id: \.section) { group in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: group.section.symbol).foregroundStyle(Theme.hardwood)
                        Eyebrow(group.section.title, color: Theme.textPrimary)
                        Text("\(group.items.filter { !$0.isChecked }.count)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 4)
                    VStack(spacing: 0) {
                        ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                            GroceryRow(item: item, compact: compact)
                            if index < group.items.count - 1 { Divider().padding(.leading, compact ? 52 : 46) }
                        }
                    }
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke))
                }
            }
        }
    }

    private var addRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill").foregroundStyle(Theme.hardwood)
            TextField("Add item", text: $newName)
                .textFieldStyle(.plain)
                .focused($nameFocused)
                .onSubmit(add)
            if !compact {
                TextField("Amount", text: $newAmount)
                    .textFieldStyle(.plain)
                    .frame(width: 90)
                    .onSubmit(add)
                Picker("Aisle", selection: $newSection) {
                    ForEach(StoreSection.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(width: 140)
            }
            Button("Add", action: add)
                .buttonStyle(HardwoodButtonStyle(compact: true))
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke))
    }

    private func add() {
        withAnimation(.spring) {
            GroceryActions.addManual(name: newName, amount: newAmount, section: newSection, context: context)
        }
        newName = ""
        newAmount = ""
        nameFocused = true
    }
}

struct GroceryRow: View {
    @Environment(\.modelContext) private var context
    @Bindable var item: GroceryItemRecord
    var compact: Bool

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { item.isChecked.toggle() }
            try? context.save()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: compact ? 24 : 19, weight: .medium))
                    .foregroundStyle(item.isChecked ? Theme.net : Theme.textSecondary)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(.system(size: compact ? 15 : 14, weight: .semibold))
                        .strikethrough(item.isChecked)
                        .foregroundStyle(item.isChecked ? Theme.textSecondary : Theme.textPrimary)
                    if compact && !item.amountText.isEmpty {
                        Text(item.amountText).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
                if item.isManual { Text("ADDED").font(.system(size: 8, weight: .heavy)).foregroundStyle(Theme.textSecondary) }
                if !compact {
                    Text(item.amountText)
                        .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(item.isChecked ? Theme.textSecondary : Theme.scoreboard)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, compact ? 12 : 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Remove", systemImage: "trash", role: .destructive) {
                context.delete(item)
                try? context.save()
            }
        }
    }
}

/// Phone-sized window for checking things off in the store.
struct GroceryPopoutView: View {
    @Query(sort: \GroceryItemRecord.sortIndex) private var items: [GroceryItemRecord]

    var body: some View {
        let done = items.filter(\.isChecked).count
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Eyebrow("Grocery run", color: Theme.hardwood)
                        Text("\(done) of \(items.count)").font(.scoreboard(26)).foregroundStyle(Theme.textPrimary)
                    }
                    Spacer()
                    AppMark(size: 34)
                }
                XPBar(progress: items.isEmpty ? 0 : Double(done) / Double(items.count), height: 10, color: Theme.net)
                if items.isEmpty {
                    Text("Generate a list from the Grocery screen first.")
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    GroceryListContent(items: items, compact: true)
                }
            }
            .padding(16)
        }
        .frame(minWidth: 320, minHeight: 480)
        .pageBackground()
    }
}

nonisolated struct PlainTextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        text = configuration.file.regularFileContents.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
