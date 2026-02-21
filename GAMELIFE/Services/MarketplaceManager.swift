//
//  MarketplaceManager.swift
//  GAMELIFE
//
//  [SYSTEM]: Marketplace terminal initialized.
//  Exchange your gold for real-world rewards.
//

import Foundation
import SwiftUI
import Combine

// MARK: - Marketplace Manager

/// Manages the reward marketplace where players spend gold on real-life rewards
@MainActor
class MarketplaceManager: ObservableObject {

    static let shared = MarketplaceManager()

    // MARK: - Published Properties

    @Published var availableRewards: [MarketplaceReward] = []
    @Published var purchaseHistory: [RewardPurchase] = []
    @Published var unredeemedRewards: [RewardPurchase] = []

    // MARK: - Initialization

    private init() {
        loadDefaultRewards()
        loadCustomRewards()
        loadPurchaseHistory()
    }

    // MARK: - Reward Management

    /// Load default marketplace rewards
    private func loadDefaultRewards() {
        availableRewards = [
            // Small Rewards (10-50 Gold)
            MarketplaceReward(
                name: "Extra Snack",
                description: "Treat yourself to a snack of your choice.",
                cost: 10,
                category: .treat,
                icon: "takeoutbag.and.cup.and.straw"
            ),
            MarketplaceReward(
                name: "15-Min Break",
                description: "Take a guilt-free 15-minute break to do whatever.",
                cost: 15,
                category: .time,
                icon: "timer"
            ),
            MarketplaceReward(
                name: "Episode Pass",
                description: "Watch one episode of your favorite show.",
                cost: 25,
                category: .entertainment,
                icon: "tv"
            ),

            // Medium Rewards (50-200 Gold)
            MarketplaceReward(
                name: "Cheat Meal",
                description: "Order your favorite food guilt-free.",
                cost: 100,
                category: .treat,
                icon: "fork.knife"
            ),
            MarketplaceReward(
                name: "Game Time",
                description: "1 hour of uninterrupted gaming.",
                cost: 75,
                category: .entertainment,
                icon: "gamecontroller"
            ),
            MarketplaceReward(
                name: "Sleep In",
                description: "Sleep in tomorrow without the guilt.",
                cost: 80,
                category: .time,
                icon: "bed.double"
            ),
            MarketplaceReward(
                name: "Coffee Upgrade",
                description: "Get your favorite fancy coffee drink.",
                cost: 50,
                category: .treat,
                icon: "cup.and.saucer"
            ),
            MarketplaceReward(
                name: "Health Potion",
                description: "Restore +25 HP instantly.",
                cost: 35,
                category: .item,
                icon: "cross.case.fill",
                healthRestore: 25
            ),
            MarketplaceReward(
                name: "Movie Night",
                description: "Watch a full movie of your choice.",
                cost: 150,
                category: .entertainment,
                icon: "popcorn"
            ),

            // Large Rewards (200-500 Gold)
            MarketplaceReward(
                name: "Self-Care Day",
                description: "Take a full day off for self-care.",
                cost: 300,
                category: .time,
                icon: "sparkles"
            ),
            MarketplaceReward(
                name: "New Book",
                description: "Buy yourself a new book.",
                cost: 200,
                category: .item,
                icon: "book"
            ),
            MarketplaceReward(
                name: "Nice Dinner",
                description: "Treat yourself to a nice restaurant dinner.",
                cost: 400,
                category: .treat,
                icon: "wineglass"
            ),
            MarketplaceReward(
                name: "Subscription Month",
                description: "One month of a streaming service of your choice.",
                cost: 350,
                category: .entertainment,
                icon: "play.circle"
            ),

            // Premium Rewards (500+ Gold)
            MarketplaceReward(
                name: "Day Trip",
                description: "Take a day trip somewhere fun.",
                cost: 750,
                category: .experience,
                icon: "car"
            ),
            MarketplaceReward(
                name: "New Gear",
                description: "Buy yourself a piece of equipment/gear you've been wanting.",
                cost: 1000,
                category: .item,
                icon: "bag"
            ),
            MarketplaceReward(
                name: "Weekend Getaway",
                description: "Plan a weekend getaway for yourself.",
                cost: 2000,
                category: .experience,
                icon: "airplane"
            ),
            MarketplaceReward(
                name: "Major Purchase",
                description: "That thing you've been saving for? You've earned it.",
                cost: 5000,
                category: .item,
                icon: "star.fill"
            )
        ]
    }

    // MARK: - Purchase Flow

    /// Purchase a reward
    func purchaseReward(_ reward: MarketplaceReward, player: inout Player) -> PurchaseResult {
        // Check if player has enough gold
        guard player.gold >= reward.cost else {
            return PurchaseResult(
                success: false,
                message: "Insufficient gold. You need \(reward.cost - player.gold) more."
            )
        }

        if let healthRestore = reward.healthRestore, healthRestore > 0, player.currentHP >= player.maxHP {
            return PurchaseResult(
                success: false,
                message: "HP is already full. Use this when you need healing."
            )
        }

        // Deduct gold
        player.gold -= reward.cost

        // Create purchase record
        var purchase = RewardPurchase(
            reward: reward,
            purchaseDate: Date()
        )

        purchaseHistory.append(purchase)

        if let healthRestore = reward.healthRestore, healthRestore > 0 {
            let hpBefore = player.currentHP
            player.currentHP = min(player.maxHP, player.currentHP + healthRestore)
            let restoredAmount = max(0, player.currentHP - hpBefore)

            purchase.isRedeemed = true
            purchase.redeemedDate = Date()
            if let historyIndex = purchaseHistory.firstIndex(where: { $0.id == purchase.id }) {
                purchaseHistory[historyIndex] = purchase
            }

            savePurchaseHistory()

            GameEngine.shared.recordExternalActivity(
                type: .rewardConsumed,
                title: reward.name,
                detail: restoredAmount > 0
                    ? "+\(restoredAmount) HP restored"
                    : "HP already full"
            )

            return PurchaseResult(
                success: true,
                message: restoredAmount > 0
                    ? "Health restored by \(restoredAmount) HP."
                    : "HP is already full.",
                purchase: purchase
            )
        }

        unredeemedRewards.append(purchase)

        // Save
        savePurchaseHistory()
        GameEngine.shared.save()

        return PurchaseResult(
            success: true,
            message: "Reward purchased! Remember to redeem it.",
            purchase: purchase
        )
    }

    /// Redeem a purchased reward
    func redeemReward(_ purchase: RewardPurchase) {
        guard let index = unredeemedRewards.firstIndex(where: { $0.id == purchase.id }) else { return }

        unredeemedRewards[index].isRedeemed = true
        unredeemedRewards[index].redeemedDate = Date()

        // Update in history too
        if let historyIndex = purchaseHistory.firstIndex(where: { $0.id == purchase.id }) {
            purchaseHistory[historyIndex] = unredeemedRewards[index]
        }

        unredeemedRewards.remove(at: index)

        GameEngine.shared.recordExternalActivity(
            type: .rewardConsumed,
            title: purchase.reward.name,
            detail: "Shop reward redeemed"
        )

        savePurchaseHistory()
    }

    // MARK: - Custom Rewards

    /// Add a custom reward
    func addCustomReward(
        name: String,
        description: String,
        cost: Int,
        category: RewardCategory
    ) {
        let reward = MarketplaceReward(
            name: name,
            description: description,
            cost: cost,
            category: category,
            icon: category.defaultIcon,
            isCustom: true
        )

        availableRewards.append(reward)
        saveCustomRewards()
    }

    /// Remove a custom reward
    func removeCustomReward(_ reward: MarketplaceReward) {
        guard reward.isCustom else { return }
        availableRewards.removeAll { $0.id == reward.id }
        saveCustomRewards()
    }

    // MARK: - Persistence

    private func savePurchaseHistory() {
        if let data = try? JSONEncoder().encode(purchaseHistory) {
            UserDefaults.standard.set(data, forKey: "rewardPurchaseHistory")
        }
        if let data = try? JSONEncoder().encode(unredeemedRewards) {
            UserDefaults.standard.set(data, forKey: "unredeemedRewards")
        }
    }

    private func loadPurchaseHistory() {
        if let data = UserDefaults.standard.data(forKey: "rewardPurchaseHistory"),
           let history = try? JSONDecoder().decode([RewardPurchase].self, from: data) {
            purchaseHistory = history
        }
        if let data = UserDefaults.standard.data(forKey: "unredeemedRewards"),
           let unredeemed = try? JSONDecoder().decode([RewardPurchase].self, from: data) {
            unredeemedRewards = unredeemed
        }
    }

    private func saveCustomRewards() {
        let customRewards = availableRewards.filter { $0.isCustom }
        if let data = try? JSONEncoder().encode(customRewards) {
            UserDefaults.standard.set(data, forKey: "customRewards")
        }
    }

    private func loadCustomRewards() {
        guard let data = UserDefaults.standard.data(forKey: "customRewards"),
              let customRewards = try? JSONDecoder().decode([MarketplaceReward].self, from: data) else {
            return
        }

        let existingIDs = Set(availableRewards.map(\.id))
        let uniqueCustomRewards = customRewards.filter { !existingIDs.contains($0.id) }
        availableRewards.append(contentsOf: uniqueCustomRewards)
    }

    func resetForFreshStart() {
        loadDefaultRewards()
        purchaseHistory = []
        unredeemedRewards = []
    }
}

// MARK: - Marketplace Reward

struct MarketplaceReward: Codable, Identifiable {
    let id: UUID
    let name: String
    let description: String
    let cost: Int
    let category: RewardCategory
    let icon: String
    var isCustom: Bool
    var healthRestore: Int?

    init(
        name: String,
        description: String,
        cost: Int,
        category: RewardCategory,
        icon: String,
        isCustom: Bool = false,
        healthRestore: Int? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.description = description
        self.cost = cost
        self.category = category
        self.icon = icon
        self.isCustom = isCustom
        self.healthRestore = healthRestore
    }
}

// MARK: - Reward Category

enum RewardCategory: String, Codable, CaseIterable {
    case treat = "Treats"
    case entertainment = "Entertainment"
    case time = "Time Off"
    case item = "Items"
    case experience = "Experiences"

    var color: Color {
        switch self {
        case .treat: return SystemTheme.warningOrange
        case .entertainment: return SystemTheme.primaryPurple
        case .time: return SystemTheme.primaryBlue
        case .item: return SystemTheme.goldColor
        case .experience: return SystemTheme.successGreen
        }
    }

    var defaultIcon: String {
        switch self {
        case .treat: return "gift"
        case .entertainment: return "play.circle"
        case .time: return "clock"
        case .item: return "bag"
        case .experience: return "star"
        }
    }
}

// MARK: - Reward Purchase

struct RewardPurchase: Codable, Identifiable {
    let id: UUID
    let reward: MarketplaceReward
    let purchaseDate: Date
    var isRedeemed: Bool
    var redeemedDate: Date?

    init(reward: MarketplaceReward, purchaseDate: Date) {
        self.id = UUID()
        self.reward = reward
        self.purchaseDate = purchaseDate
        self.isRedeemed = false
        self.redeemedDate = nil
    }
}

// MARK: - Purchase Result

struct PurchaseResult {
    let success: Bool
    let message: String
    var purchase: RewardPurchase?
}

// MARK: - Marketplace View

struct MarketplaceView: View {
    @StateObject private var marketplaceManager = MarketplaceManager.shared
    @ObservedObject var gameEngine: GameEngine
    @State private var selectedCategory: RewardCategory?
    @State private var showPurchaseConfirmation = false
    @State private var selectedReward: MarketplaceReward?
    @State private var purchaseResult: PurchaseResult?

    var filteredRewards: [MarketplaceReward] {
        if let category = selectedCategory {
            return marketplaceManager.availableRewards.filter { $0.category == category }
        }
        return marketplaceManager.availableRewards.sorted { $0.cost < $1.cost }
    }

    var body: some View {
        ZStack {
            SystemTheme.backgroundPrimary
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                MarketplaceHeaderView(gold: gameEngine.player.gold)

                // Category filter
                CategoryFilterView(selectedCategory: $selectedCategory)

                // Rewards list
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        // Unredeemed rewards section
                        if !marketplaceManager.unredeemedRewards.isEmpty {
                            UnredeemedRewardsSection(
                                rewards: marketplaceManager.unredeemedRewards,
                                onRedeem: marketplaceManager.redeemReward
                            )
                        }

                        // Available rewards
                        ForEach(filteredRewards) { reward in
                            RewardCardView(
                                reward: reward,
                                canAfford: gameEngine.player.gold >= reward.cost
                            ) {
                                selectedReward = reward
                                showPurchaseConfirmation = true
                            }
                        }
                    }
                    .padding()
                }
            }

            // Purchase confirmation
            if showPurchaseConfirmation, let reward = selectedReward {
                PurchaseConfirmationOverlay(
                    reward: reward,
                    currentGold: gameEngine.player.gold,
                    onConfirm: {
                        purchaseResult = marketplaceManager.purchaseReward(
                            reward,
                            player: &gameEngine.player
                        )
                        showPurchaseConfirmation = false
                    },
                    onCancel: {
                        showPurchaseConfirmation = false
                        selectedReward = nil
                    }
                )
            }
        }
    }
}

// MARK: - Marketplace Header

struct MarketplaceHeaderView: View {
    let gold: Int

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("[MARKETPLACE]")
                    .font(SystemTypography.systemTitle)
                    .foregroundStyle(SystemTheme.goldColor)

                Text("Exchange gold for real-world rewards")
                    .font(SystemTypography.caption)
                    .foregroundStyle(SystemTheme.textTertiary)
            }

            Spacer()

            // Gold balance
            HStack(spacing: 8) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(SystemTheme.goldColor)

                Text("\(gold)")
                    .font(SystemTypography.statSmall)
                    .foregroundStyle(SystemTheme.goldColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(SystemTheme.goldColor.opacity(0.15))
            .clipShape(Capsule())
        }
        .padding()
        .background(SystemTheme.backgroundSecondary)
    }
}

// MARK: - Category Filter

struct CategoryFilterView: View {
    @Binding var selectedCategory: RewardCategory?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // All button
                CategoryButton(
                    title: "All",
                    isSelected: selectedCategory == nil,
                    color: SystemTheme.primaryBlue
                ) {
                    selectedCategory = nil
                }

                // Category buttons
                ForEach(RewardCategory.allCases, id: \.self) { category in
                    CategoryButton(
                        title: category.rawValue,
                        isSelected: selectedCategory == category,
                        color: category.color
                    ) {
                        selectedCategory = category
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(SystemTheme.backgroundSecondary)
    }
}

struct CategoryButton: View {
    let title: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(SystemTypography.caption)
                .foregroundStyle(isSelected ? SystemTheme.backgroundPrimary : color)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? color : color.opacity(0.15))
                .clipShape(Capsule())
        }
    }
}

// MARK: - Reward Card

struct RewardCardView: View {
    let reward: MarketplaceReward
    let canAfford: Bool
    let onPurchase: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(reward.category.color.opacity(0.2))
                    .frame(width: 50, height: 50)

                Image(systemName: reward.icon)
                    .font(.system(size: 24))
                    .foregroundStyle(reward.category.color)
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(reward.name)
                    .font(SystemTypography.headline)
                    .foregroundStyle(canAfford ? SystemTheme.textPrimary : SystemTheme.textTertiary)

                Text(reward.description)
                    .font(SystemTypography.caption)
                    .foregroundStyle(SystemTheme.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            // Price and buy button
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "dollarsign.circle.fill")
                        .foregroundStyle(SystemTheme.goldColor)
                    Text("\(reward.cost)")
                        .font(SystemTypography.goldCounter)
                        .foregroundStyle(SystemTheme.goldColor)
                }

                Button(action: onPurchase) {
                    Text("BUY")
                        .font(SystemTypography.mono(12, weight: .bold))
                        .foregroundStyle(canAfford ? SystemTheme.backgroundPrimary : SystemTheme.textTertiary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(canAfford ? SystemTheme.goldColor : SystemTheme.backgroundTertiary)
                        .clipShape(Capsule())
                }
                .disabled(!canAfford)
            }
        }
        .padding()
        .systemCard()
        .opacity(canAfford ? 1.0 : 0.6)
    }
}

// MARK: - Unredeemed Rewards Section

struct UnredeemedRewardsSection: View {
    let rewards: [RewardPurchase]
    let onRedeem: (RewardPurchase) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("UNREDEEMED REWARDS")
                .font(SystemTypography.systemMessage)
                .foregroundStyle(SystemTheme.successGreen)

            ForEach(rewards) { purchase in
                HStack {
                    Image(systemName: purchase.reward.icon)
                        .foregroundStyle(purchase.reward.category.color)

                    Text(purchase.reward.name)
                        .font(SystemTypography.body)
                        .foregroundStyle(SystemTheme.textPrimary)

                    Spacer()

                    Button("REDEEM") {
                        onRedeem(purchase)
                    }
                    .font(SystemTypography.mono(12, weight: .bold))
                    .foregroundStyle(SystemTheme.backgroundPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(SystemTheme.successGreen)
                    .clipShape(Capsule())
                }
                .padding()
                .background(SystemTheme.successGreen.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: SystemRadius.medium))
            }
        }
        .padding()
        .systemCard()
    }
}

// MARK: - Purchase Confirmation Overlay

struct PurchaseConfirmationOverlay: View {
    let reward: MarketplaceReward
    let currentGold: Int
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(spacing: 24) {
                Text("CONFIRM PURCHASE")
                    .font(SystemTypography.titleSmall)
                    .foregroundStyle(SystemTheme.textPrimary)

                // Reward info
                VStack(spacing: 12) {
                    Image(systemName: reward.icon)
                        .font(.system(size: 48))
                        .foregroundStyle(reward.category.color)

                    Text(reward.name)
                        .font(SystemTypography.headline)
                        .foregroundStyle(SystemTheme.textPrimary)

                    HStack(spacing: 4) {
                        Image(systemName: "dollarsign.circle.fill")
                            .foregroundStyle(SystemTheme.goldColor)
                        Text("\(reward.cost)")
                            .font(SystemTypography.statSmall)
                            .foregroundStyle(SystemTheme.goldColor)
                    }
                }

                // Gold balance after
                VStack(spacing: 4) {
                    Text("After purchase:")
                        .font(SystemTypography.caption)
                        .foregroundStyle(SystemTheme.textTertiary)

                    Text("\(currentGold) → \(currentGold - reward.cost) Gold")
                        .font(SystemTypography.mono(14, weight: .semibold))
                        .foregroundStyle(SystemTheme.textSecondary)
                }

                // Buttons
                HStack(spacing: 16) {
                    Button(action: onCancel) {
                        Text("CANCEL")
                            .font(SystemTypography.mono(14, weight: .bold))
                            .foregroundStyle(SystemTheme.textSecondary)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 12)
                            .background(SystemTheme.backgroundTertiary)
                            .clipShape(Capsule())
                    }

                    Button(action: onConfirm) {
                        Text("CONFIRM")
                            .font(SystemTypography.mono(14, weight: .bold))
                            .foregroundStyle(SystemTheme.backgroundPrimary)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 12)
                            .background(SystemTheme.goldColor)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(32)
            .systemCard(elevated: true)
        }
    }
}
