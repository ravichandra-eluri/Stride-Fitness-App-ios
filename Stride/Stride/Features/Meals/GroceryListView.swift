import SwiftUI

// ── Grocery List ViewModel ────────────────────────────────────────────────────

@Observable
@MainActor
final class GroceryListViewModel {
    var list: GroceryList?
    var isLoading = true
    var isRefreshing = false
    var error: String?

    /// Item names the user has ticked off, keyed in UserDefaults by meal plan id
    /// so a regenerated plan starts with a clean slate.
    var checked: Set<String> = []

    func load() async {
        isLoading = true
        error = nil
        do {
            list = try await APIClient.shared.getGroceryList()
            checked = loadChecked(for: list?.mealPlanId ?? "")
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func refresh() async {
        isRefreshing = true
        error = nil
        do {
            list = try await APIClient.shared.getGroceryList(force: true)
            checked = loadChecked(for: list?.mealPlanId ?? "")
        } catch {
            self.error = error.localizedDescription
        }
        isRefreshing = false
    }

    func toggle(_ item: GroceryItem) {
        if checked.contains(item.name) {
            checked.remove(item.name)
        } else {
            checked.insert(item.name)
            Haptics.impact(.light)
        }
        persistChecked()
    }

    /// Plain-text dump for the iOS share sheet.
    func shareText() -> String {
        guard let list else { return "" }
        var out = "Grocery list — \(list.week)\n"
        for cat in list.categories {
            out += "\n\(cat.name)\n"
            for item in cat.items {
                let mark = checked.contains(item.name) ? "[x]" : "[ ]"
                out += "  \(mark) \(item.name) — \(item.quantity)\n"
            }
        }
        return out
    }

    private func checkedKey(_ mealPlanID: String) -> String {
        "grocery_checked_\(mealPlanID)"
    }

    private func loadChecked(for mealPlanID: String) -> Set<String> {
        let arr = UserDefaults.standard.stringArray(forKey: checkedKey(mealPlanID)) ?? []
        return Set(arr)
    }

    private func persistChecked() {
        guard let id = list?.mealPlanId else { return }
        UserDefaults.standard.set(Array(checked), forKey: checkedKey(id))
    }
}

// ── Grocery List View ─────────────────────────────────────────────────────────

struct GroceryListView: View {
    @State private var vm = GroceryListViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if vm.isLoading {
                WLoadingView(message: "Building your grocery list...")
            } else if vm.isRefreshing {
                WLoadingView(message: "Regenerating from your meal plan...")
            } else if let error = vm.error {
                WErrorView(message: error) { Task { await vm.load() } }
            } else if let list = vm.list, !list.categories.isEmpty {
                content(list)
            } else {
                WEmptyState(
                    icon: "basket",
                    title: "Nothing to shop for",
                    subtitle: "Generate a meal plan first and your grocery list will appear here."
                )
            }
        }
        .navigationTitle("Grocery list")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Task { await vm.refresh() }
                    } label: {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                    }
                    if vm.list != nil {
                        ShareLink(item: vm.shareText()) {
                            Label("Share as text", systemImage: "square.and.arrow.up")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.primary)
                }
            }
        }
        .task { await vm.load() }
    }

    private func content(_ list: GroceryList) -> some View {
        let totalItems = list.categories.reduce(0) { $0 + $1.items.count }
        let checkedCount = vm.checked.count

        return ScrollView {
            VStack(spacing: Spacing.md) {
                // Header summary
                WCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(list.week)
                                .font(.titleSm)
                            Text("\(totalItems) items · \(checkedCount) checked")
                                .font(.bodySm)
                                .foregroundColor(.textMuted)
                        }
                        Spacer()
                        ZStack {
                            Circle()
                                .fill(Color.brandGreenBg)
                                .frame(width: 44, height: 44)
                            Image(systemName: "basket.fill")
                                .foregroundColor(.brandGreen)
                        }
                    }
                }

                ForEach(list.categories) { cat in
                    categorySection(cat)
                }
            }
            .padding(Spacing.md)
        }
        .refreshable { await vm.load() }
    }

    private func categorySection(_ cat: GroceryCategory) -> some View {
        WCard(padding: 0) {
            VStack(spacing: 0) {
                HStack {
                    Label(cat.name, systemImage: categoryIcon(cat.name))
                        .font(.labelSm)
                        .foregroundColor(categoryColor(cat.name))
                    Spacer()
                    Text("\(cat.items.count)")
                        .font(.labelSm)
                        .foregroundColor(.textMuted)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xs)

                Divider()

                ForEach(Array(cat.items.enumerated()), id: \.element.id) { i, item in
                    itemRow(item)
                    if i < cat.items.count - 1 {
                        Divider().padding(.leading, Spacing.md)
                    }
                }
            }
        }
    }

    private func itemRow(_ item: GroceryItem) -> some View {
        let isChecked = vm.checked.contains(item.name)
        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                vm.toggle(item)
            }
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(isChecked ? .brandGreen : .textMuted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.labelMd)
                        .foregroundColor(isChecked ? .textMuted : .primary)
                        .strikethrough(isChecked)
                    Text(item.quantity)
                        .font(.bodySm)
                        .foregroundColor(.textMuted)
                }
                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func categoryIcon(_ name: String) -> String {
        switch name.lowercased() {
        case let s where s.contains("produce"):  return "leaf.fill"
        case let s where s.contains("protein"):  return "fish.fill"
        case let s where s.contains("grain"):    return "takeoutbag.and.cup.and.straw.fill"
        case let s where s.contains("dairy"):    return "drop.fill"
        case let s where s.contains("pantry"):   return "cabinet.fill"
        default:                                 return "bag.fill"
        }
    }

    private func categoryColor(_ name: String) -> Color {
        switch name.lowercased() {
        case let s where s.contains("produce"):  return .brandGreen
        case let s where s.contains("protein"):  return .infoText
        case let s where s.contains("grain"):    return .warning
        case let s where s.contains("dairy"):    return .brandPurple
        case let s where s.contains("pantry"):   return .textMuted
        default:                                 return .textMuted
        }
    }
}
