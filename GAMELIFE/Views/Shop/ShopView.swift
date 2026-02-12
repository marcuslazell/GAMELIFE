//
//  ShopView.swift
//  GAMELIFE
//
//  [SYSTEM]: Marketplace terminal accessed.
//  Your hard-earned gold awaits conversion.
//

import SwiftUI

// MARK: - Shop View

/// Tab 5: Wrapper for the Marketplace reward system
struct ShopView: View {

    // MARK: - Properties

    @EnvironmentObject var gameEngine: GameEngine
    @State private var showAddReward = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            MarketplaceView(gameEngine: gameEngine)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showAddReward = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(SystemTheme.goldColor)
                        }
                    }
                }
                .toolbarBackground(SystemTheme.backgroundSecondary, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .sheet(isPresented: $showAddReward) {
                    CustomRewardSheet()
                }
        }
    }
}

// MARK: - Custom Reward Sheet

struct CustomRewardSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var marketplaceManager = MarketplaceManager.shared

    @State private var name = ""
    @State private var description = ""
    @State private var cost = 50
    @State private var category: RewardCategory = .treat

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && cost > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Reward Name", text: $name)
                        .font(SystemTypography.body)

                    TextField("Description", text: $description)
                        .font(SystemTypography.body)
                } header: {
                    Text("Reward Details")
                }

                Section {
                    Picker("Category", selection: $category) {
                        ForEach(RewardCategory.allCases, id: \.self) { cat in
                            HStack {
                                Image(systemName: cat.defaultIcon)
                                    .foregroundStyle(cat.color)
                                Text(cat.rawValue)
                            }
                            .tag(cat)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Cost:")
                                .foregroundStyle(SystemTheme.textSecondary)

                            Spacer()

                            HStack(spacing: 4) {
                                Image(systemName: "dollarsign.circle.fill")
                                    .foregroundStyle(SystemTheme.goldColor)
                                Text("\(cost)")
                                    .font(SystemTypography.mono(16, weight: .bold))
                                    .foregroundStyle(SystemTheme.goldColor)
                            }
                        }

                        Slider(value: Binding(
                            get: { Double(cost) },
                            set: { cost = Int($0) }
                        ), in: 10...2000, step: 10)
                        .tint(SystemTheme.goldColor)
                    }
                } header: {
                    Text("Pricing")
                }

                Section {
                    HStack {
                        Image(systemName: category.defaultIcon)
                            .font(.system(size: 24))
                            .foregroundStyle(category.color)
                            .frame(width: 40)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(name.isEmpty ? "Reward Name" : name)
                                .font(SystemTypography.headline)
                                .foregroundStyle(name.isEmpty ? SystemTheme.textTertiary : SystemTheme.textPrimary)

                            Text(description.isEmpty ? "Description" : description)
                                .font(SystemTypography.caption)
                                .foregroundStyle(SystemTheme.textSecondary)
                        }

                        Spacer()

                        HStack(spacing: 4) {
                            Image(systemName: "dollarsign.circle.fill")
                                .foregroundStyle(SystemTheme.goldColor)
                            Text("\(cost)")
                                .font(SystemTypography.mono(14, weight: .bold))
                                .foregroundStyle(SystemTheme.goldColor)
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Preview")
                }
            }
            .navigationTitle("Custom Reward")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addReward() }
                        .disabled(!isValid)
                }
            }
        }
    }

    private func addReward() {
        marketplaceManager.addCustomReward(
            name: name.trimmingCharacters(in: .whitespaces),
            description: description.trimmingCharacters(in: .whitespaces).isEmpty
                ? "A custom reward you've earned."
                : description.trimmingCharacters(in: .whitespaces),
            cost: cost,
            category: category
        )

        SystemMessageHelper.show(SystemMessage(
            type: .success,
            title: "Reward Added",
            message: "\(name) is now available in the shop"
        ))

        dismiss()
    }
}

// MARK: - Preview

#Preview {
    ShopView()
        .environmentObject(GameEngine.shared)
}
