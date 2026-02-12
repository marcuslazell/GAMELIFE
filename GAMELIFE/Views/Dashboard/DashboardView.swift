//
//  DashboardView.swift
//  GAMELIFE
//
//  [SYSTEM]: Status window activated.
//  Your power level is now visible.
//

import SwiftUI
import Combine

// MARK: - Dashboard View

/// The main hub - displays player status, quests, and quick actions
struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @State private var selectedTab: DashboardTab = .status
    @State private var showQuestComplete = false
    @State private var completedQuestReward: QuestReward?

    var body: some View {
        ZStack {
            // Background
            SystemTheme.backgroundPrimary
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                DashboardHeaderView(player: viewModel.player)

                // Tab selector
                DashboardTabBar(selectedTab: $selectedTab)

                // Content
                ScrollView(showsIndicators: false) {
                    VStack(spacing: SystemSpacing.lg) {
                        switch selectedTab {
                        case .status:
                            StatusTabContent(player: viewModel.player)

                        case .quests:
                            QuestsTabContent(
                                dailyQuests: viewModel.dailyQuests,
                                onQuestComplete: { quest, reward in
                                    completedQuestReward = reward
                                    showQuestComplete = true
                                    viewModel.completeQuest(quest)
                                }
                            )

                        case .bosses:
                            BossesTabContent(
                                bossFights: viewModel.bossFights,
                                onDealDamage: viewModel.dealBossDamage
                            )

                        case .dungeon:
                            DungeonTabContent(viewModel: viewModel)
                        }
                    }
                    .padding()
                }
            }

            // Quest complete overlay
            if showQuestComplete, let reward = completedQuestReward {
                QuestCompleteOverlay(reward: reward) {
                    withAnimation {
                        showQuestComplete = false
                        completedQuestReward = nil
                    }
                }
            }
        }
    }
}

// MARK: - Dashboard Tab

enum DashboardTab: String, CaseIterable {
    case status = "Status"
    case quests = "Quests"
    case bosses = "Bosses"
    case dungeon = "Dungeon"

    var icon: String {
        switch self {
        case .status: return "person.fill"
        case .quests: return "list.bullet.rectangle"
        case .bosses: return "bolt.shield.fill"
        case .dungeon: return "door.left.hand.closed"
        }
    }
}

// MARK: - Dashboard Header

struct DashboardHeaderView: View {
    let player: Player

    @State private var glowIntensity: Double = 0.5

    var body: some View {
        HStack(alignment: .top, spacing: SystemSpacing.md) {
            // Player avatar/rank badge
            VStack {
                ZStack {
                    // Rank badge background
                    Circle()
                        .fill(player.rank.glowColor.opacity(0.2))
                        .frame(width: 60, height: 60)

                    Circle()
                        .stroke(player.rank.glowColor, lineWidth: 2)
                        .frame(width: 60, height: 60)
                        .glow(color: player.rank.glowColor, radius: 8 * glowIntensity)

                    Text(player.rank.rawValue)
                        .font(SystemTypography.mono(20, weight: .bold))
                        .foregroundStyle(player.rank.glowColor)
                }

                Text("Rank")
                    .font(SystemTypography.captionSmall)
                    .foregroundStyle(SystemTheme.textTertiary)
            }

            // Player info
            VStack(alignment: .leading, spacing: 4) {
                Text(player.name)
                    .font(SystemTypography.titleSmall)
                    .foregroundStyle(SystemTheme.textPrimary)

                Text(player.title)
                    .font(SystemTypography.caption)
                    .foregroundStyle(SystemTheme.primaryBlue)

                // Level and XP bar
                HStack(spacing: 8) {
                    Text("Lv. \(player.level)")
                        .font(SystemTypography.mono(14, weight: .bold))
                        .foregroundStyle(SystemTheme.textPrimary)

                    // XP progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(SystemTheme.backgroundSecondary)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(SystemTheme.xpGradient)
                                .frame(width: geometry.size.width * player.xpProgress)
                        }
                    }
                    .frame(height: 8)
                }
                .padding(.top, 4)

                Text("\(player.currentXP) / \(player.xpRequiredForNextLevel) XP")
                    .font(SystemTypography.captionSmall)
                    .foregroundStyle(SystemTheme.textTertiary)
            }

            Spacer()

            // Gold display
            VStack(alignment: .trailing) {
                HStack(spacing: 4) {
                    Image(systemName: "dollarsign.circle.fill")
                        .foregroundStyle(SystemTheme.goldColor)

                    Text("\(player.gold)")
                        .font(SystemTypography.goldCounter)
                        .foregroundStyle(SystemTheme.goldColor)
                }

                // Streak display
                if player.currentStreak > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(SystemTheme.warningOrange)
                            .font(.system(size: 12))

                        Text("\(player.currentStreak) day streak")
                            .font(SystemTypography.captionSmall)
                            .foregroundStyle(SystemTheme.warningOrange)
                    }
                }
            }
        }
        .padding()
        .background(SystemTheme.backgroundSecondary)
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                glowIntensity = 1.0
            }
        }
    }
}

// MARK: - Dashboard Tab Bar

struct DashboardTabBar: View {
    @Binding var selectedTab: DashboardTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(DashboardTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18))

                        Text(tab.rawValue)
                            .font(SystemTypography.captionSmall)
                    }
                    .foregroundStyle(selectedTab == tab ? SystemTheme.primaryBlue : SystemTheme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        selectedTab == tab ?
                        SystemTheme.primaryBlue.opacity(0.1) :
                        Color.clear
                    )
                }
            }
        }
        .background(SystemTheme.backgroundSecondary)
        .overlay(
            Rectangle()
                .fill(SystemTheme.borderPrimary)
                .frame(height: 1),
            alignment: .bottom
        )
    }
}

// MARK: - Status Tab Content

struct StatusTabContent: View {
    let player: Player

    var body: some View {
        VStack(spacing: SystemSpacing.lg) {
            // Stats radar chart
            VStack(spacing: SystemSpacing.sm) {
                HStack {
                    Text("[STATUS]")
                        .font(SystemTypography.systemTitle)
                        .foregroundStyle(SystemTheme.primaryBlue)

                    Spacer()

                    Text("Power: \(player.powerLevel)")
                        .font(SystemTypography.mono(14, weight: .semibold))
                        .foregroundStyle(SystemTheme.accentCyan)
                }

                RadarChartView(stats: player.statArray)
                    .frame(height: 280)
            }
            .padding()
            .systemCard()

            // Stats list detail
            VStack(spacing: SystemSpacing.sm) {
                HStack {
                    Text("[ATTRIBUTES]")
                        .font(SystemTypography.systemTitle)
                        .foregroundStyle(SystemTheme.primaryBlue)
                    Spacer()
                }

                ForEach(player.statArray) { stat in
                    StatRowView(stat: stat)
                }
            }
            .padding()
            .systemCard()

            // Origin Story
            VStack(alignment: .leading, spacing: SystemSpacing.sm) {
                HStack {
                    Text("[ORIGIN]")
                        .font(SystemTypography.systemTitle)
                        .foregroundStyle(SystemTheme.primaryPurple)
                    Spacer()
                }

                Text(player.originStory.isEmpty ? "No origin story recorded." : player.originStory)
                    .font(SystemTypography.body)
                    .foregroundStyle(SystemTheme.textSecondary)
                    .italic()
            }
            .padding()
            .systemCard()
        }
    }
}

// MARK: - Stat Row View

struct StatRowView: View {
    let stat: Stat

    var body: some View {
        HStack(spacing: SystemSpacing.md) {
            // Stat icon
            Image(systemName: stat.type.icon)
                .font(.system(size: 20))
                .foregroundStyle(stat.type.color)
                .frame(width: 32)

            // Stat name and description
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(stat.type.rawValue)
                        .font(SystemTypography.mono(14, weight: .bold))
                        .foregroundStyle(stat.type.color)

                    Text("- \(stat.type.fullName)")
                        .font(SystemTypography.caption)
                        .foregroundStyle(SystemTheme.textSecondary)
                }

                // Progress bar to next point
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(SystemTheme.backgroundSecondary)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(stat.type.color.opacity(0.7))
                            .frame(width: geometry.size.width * stat.progressToNextPoint)
                    }
                }
                .frame(height: 4)
            }

            Spacer()

            // Stat value
            Text("\(stat.totalValue)")
                .font(SystemTypography.statSmall)
                .foregroundStyle(SystemTheme.textPrimary)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Quest Reward

struct QuestReward {
    let xp: Int
    let gold: Int
    let statGains: [(StatType, Int)]
    let isCritical: Bool
    let lootBox: LootBox?
}

// MARK: - Quest Complete Overlay

struct QuestCompleteOverlay: View {
    let reward: QuestReward
    let onDismiss: () -> Void

    @State private var showContent = false
    @State private var showRewards = false

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.8)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            // Content
            VStack(spacing: 24) {
                if showContent {
                    // Title
                    VStack(spacing: 8) {
                        Text(reward.isCritical ? "CRITICAL SUCCESS!" : "QUEST COMPLETE")
                            .font(SystemTypography.titleMedium)
                            .foregroundStyle(reward.isCritical ? SystemTheme.goldColor : SystemTheme.successGreen)
                            .glow(color: reward.isCritical ? SystemTheme.goldColor : SystemTheme.successGreen, radius: 10)

                        if reward.isCritical {
                            Text("★ BONUS REWARDS ★")
                                .font(SystemTypography.systemMessage)
                                .foregroundStyle(SystemTheme.goldColor)
                        }
                    }

                    if showRewards {
                        // Rewards
                        VStack(spacing: 16) {
                            // XP
                            HStack {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(SystemTheme.primaryBlue)
                                Text("+\(reward.xp) XP")
                                    .font(SystemTypography.xpCounter)
                                    .foregroundStyle(SystemTheme.primaryBlue)
                            }

                            // Gold
                            HStack {
                                Image(systemName: "dollarsign.circle.fill")
                                    .foregroundStyle(SystemTheme.goldColor)
                                Text("+\(reward.gold) Gold")
                                    .font(SystemTypography.goldCounter)
                                    .foregroundStyle(SystemTheme.goldColor)
                            }

                            // Stat gains
                            ForEach(reward.statGains, id: \.0) { stat, amount in
                                HStack {
                                    Image(systemName: stat.icon)
                                        .foregroundStyle(stat.color)
                                    Text("+\(amount) \(stat.rawValue)")
                                        .font(SystemTypography.mono(14, weight: .semibold))
                                        .foregroundStyle(stat.color)
                                }
                            }

                            // Loot box
                            if let lootBox = reward.lootBox {
                                HStack {
                                    Image(systemName: "gift.fill")
                                        .foregroundStyle(lootBox.rarity.color)
                                    Text("\(lootBox.rarity.rawValue) Loot Box!")
                                        .font(SystemTypography.mono(14, weight: .bold))
                                        .foregroundStyle(lootBox.rarity.color)
                                }
                                .glow(color: lootBox.rarity.color, radius: 8)
                            }
                        }
                        .transition(.scale.combined(with: .opacity))
                    }

                    // Dismiss button
                    Button(action: onDismiss) {
                        Text("TAP TO CONTINUE")
                            .font(SystemTypography.systemMessage)
                            .foregroundStyle(SystemTheme.textSecondary)
                    }
                    .padding(.top, 20)
                }
            }
            .padding(32)
            .systemCard(elevated: true)
            .holographicBorder()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) {
                showContent = true
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
                showRewards = true
            }
        }
    }
}

// MARK: - Quests Tab Content

struct QuestsTabContent: View {
    let dailyQuests: [DailyQuest]
    let onQuestComplete: (DailyQuest, QuestReward) -> Void

    var body: some View {
        VStack(spacing: SystemSpacing.lg) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("[DAILY QUESTS]")
                        .font(SystemTypography.systemTitle)
                        .foregroundStyle(SystemTheme.primaryBlue)

                    Text("\"The Preparation to Become Powerful\"")
                        .font(SystemTypography.caption)
                        .foregroundStyle(SystemTheme.textTertiary)
                        .italic()
                }

                Spacer()

                // Completion count
                let completed = dailyQuests.filter { $0.status == .completed }.count
                Text("\(completed)/\(dailyQuests.count)")
                    .font(SystemTypography.mono(16, weight: .bold))
                    .foregroundStyle(completed == dailyQuests.count ? SystemTheme.successGreen : SystemTheme.textSecondary)
            }

            // Quest list
            ForEach(dailyQuests, id: \.id) { quest in
                DailyQuestRowView(quest: quest) {
                    // Calculate reward
                    let reward = QuestReward(
                        xp: quest.xpReward,
                        gold: quest.goldReward,
                        statGains: quest.targetStats.map { ($0, GameFormulas.statXP(difficulty: quest.difficulty)) },
                        isCritical: Double.random(in: 0...1) < GameFormulas.criticalSuccessChance,
                        lootBox: Double.random(in: 0...1) < GameFormulas.criticalSuccessChance ? LootBox(rarity: .rare) : nil
                    )
                    onQuestComplete(quest, reward)
                }
            }
        }
        .padding()
        .systemCard()
    }
}

// MARK: - Daily Quest Row

struct DailyQuestRowView: View {
    let quest: DailyQuest
    let onComplete: () -> Void

    var body: some View {
        HStack(spacing: SystemSpacing.md) {
            // Checkbox
            Button {
                if quest.status != .completed {
                    onComplete()
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(quest.status == .completed ? SystemTheme.successGreen : SystemTheme.borderPrimary, lineWidth: 2)
                        .frame(width: 28, height: 28)

                    if quest.status == .completed {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(SystemTheme.successGreen)
                    }
                }
            }
            .disabled(quest.status == .completed)

            // Quest info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(quest.title)
                        .font(SystemTypography.headline)
                        .foregroundStyle(quest.status == .completed ? SystemTheme.textTertiary : SystemTheme.textPrimary)
                        .strikethrough(quest.status == .completed)

                    // Difficulty badge
                    Text(quest.difficulty.rawValue)
                        .font(SystemTypography.captionSmall)
                        .foregroundStyle(quest.difficulty.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(quest.difficulty.color.opacity(0.2))
                        .clipShape(Capsule())
                }

                HStack(spacing: 12) {
                    // Tracking type
                    HStack(spacing: 4) {
                        Image(systemName: quest.trackingType.icon)
                            .font(.system(size: 10))
                        Text(quest.trackingType.isAutomatic ? "Auto" : "Manual")
                            .font(SystemTypography.captionSmall)
                    }
                    .foregroundStyle(SystemTheme.textTertiary)

                    // Progress (if applicable)
                    if quest.targetValue > 1 {
                        Text(quest.displayProgress)
                            .font(SystemTypography.captionSmall)
                            .foregroundStyle(SystemTheme.textSecondary)
                    }
                }
            }

            Spacer()

            // Rewards
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Text("+\(quest.xpReward)")
                        .font(SystemTypography.mono(12, weight: .semibold))
                    Text("XP")
                        .font(SystemTypography.captionSmall)
                }
                .foregroundStyle(SystemTheme.primaryBlue)

                // Target stats
                HStack(spacing: 4) {
                    ForEach(quest.targetStats, id: \.self) { stat in
                        Image(systemName: stat.icon)
                            .font(.system(size: 10))
                            .foregroundStyle(stat.color)
                    }
                }
            }
        }
        .padding()
        .background(quest.status == .completed ? SystemTheme.backgroundSecondary.opacity(0.5) : SystemTheme.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: SystemRadius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: SystemRadius.medium)
                .stroke(quest.status == .completed ? SystemTheme.successGreen.opacity(0.3) : SystemTheme.borderSecondary, lineWidth: 1)
        )
    }
}

// MARK: - Bosses Tab Content

struct BossesTabContent: View {
    let bossFights: [BossFight]
    let onDealDamage: (BossFight, MicroTask) -> Void

    var body: some View {
        VStack(spacing: SystemSpacing.lg) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("[BOSS FIGHTS]")
                        .font(SystemTypography.systemTitle)
                        .foregroundStyle(SystemTheme.criticalRed)

                    Text("\"Slay the monsters blocking your path\"")
                        .font(SystemTypography.caption)
                        .foregroundStyle(SystemTheme.textTertiary)
                        .italic()
                }

                Spacer()

                NavigationLink(destination: Text("Create Boss")) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(SystemTheme.primaryBlue)
                }
            }

            if bossFights.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "bolt.shield")
                        .font(.system(size: 48))
                        .foregroundStyle(SystemTheme.textTertiary)

                    Text("No active boss fights")
                        .font(SystemTypography.body)
                        .foregroundStyle(SystemTheme.textSecondary)

                    Text("Create a project to spawn a boss.")
                        .font(SystemTypography.caption)
                        .foregroundStyle(SystemTheme.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
            } else {
                ForEach(bossFights, id: \.id) { boss in
                    BossFightCardView(boss: boss, onDealDamage: onDealDamage)
                }
            }
        }
        .padding()
        .systemCard()
    }
}

// MARK: - Boss Fight Card

struct BossFightCardView: View {
    let boss: BossFight
    let onDealDamage: (BossFight, MicroTask) -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: SystemSpacing.md) {
            // Boss header with HP bar
            VStack(spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(boss.title)
                            .font(SystemTypography.headline)
                            .foregroundStyle(SystemTheme.textPrimary)

                        Text(boss.description)
                            .font(SystemTypography.caption)
                            .foregroundStyle(SystemTheme.textSecondary)
                    }

                    Spacer()

                    // Expand/collapse
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .foregroundStyle(SystemTheme.textSecondary)
                    }
                }

                // HP Bar
                VStack(spacing: 4) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(SystemTheme.backgroundSecondary)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(SystemTheme.hpGradient)
                                .frame(width: geometry.size.width * boss.hpPercentage)
                        }
                    }
                    .frame(height: 16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(SystemTheme.criticalRed.opacity(0.5), lineWidth: 1)
                    )

                    HStack {
                        Text("HP: \(boss.remainingHP) / \(boss.maxHP)")
                            .font(SystemTypography.mono(12, weight: .semibold))
                            .foregroundStyle(SystemTheme.criticalRed)

                        Spacer()

                        Text("\(Int(boss.damageDealtPercentage * 100))% defeated")
                            .font(SystemTypography.captionSmall)
                            .foregroundStyle(SystemTheme.textTertiary)
                    }
                }
            }

            // Micro-tasks (expanded)
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Micro-Tasks (Deal Damage)")
                        .font(SystemTypography.caption)
                        .foregroundStyle(SystemTheme.textSecondary)

                    ForEach(boss.microTasks) { task in
                        MicroTaskRowView(task: task) {
                            onDealDamage(boss, task)
                        }
                    }

                    // Add task button
                    Button {
                        // Add task action
                    } label: {
                        HStack {
                            Image(systemName: "plus")
                            Text("Add Attack")
                        }
                        .font(SystemTypography.caption)
                        .foregroundStyle(SystemTheme.primaryBlue)
                        .padding(.vertical, 8)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .background(SystemTheme.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: SystemRadius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: SystemRadius.medium)
                .stroke(SystemTheme.criticalRed.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Micro Task Row

struct MicroTaskRowView: View {
    let task: MicroTask
    let onComplete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onComplete) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isCompleted ? SystemTheme.successGreen : SystemTheme.textTertiary)
            }
            .disabled(task.isCompleted)

            Text(task.title)
                .font(SystemTypography.bodySmall)
                .foregroundStyle(task.isCompleted ? SystemTheme.textTertiary : SystemTheme.textPrimary)
                .strikethrough(task.isCompleted)

            Spacer()

            Text("-\(task.estimatedDamage) HP")
                .font(SystemTypography.mono(12, weight: .semibold))
                .foregroundStyle(SystemTheme.criticalRed)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(SystemTheme.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: SystemRadius.small))
    }
}

// MARK: - Dungeon Tab Content

struct DungeonTabContent: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        VStack(spacing: SystemSpacing.lg) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("[DUNGEON]")
                        .font(SystemTypography.systemTitle)
                        .foregroundStyle(SystemTheme.primaryPurple)

                    Text("\"Enter the realm of deep focus\"")
                        .font(SystemTypography.caption)
                        .foregroundStyle(SystemTheme.textTertiary)
                        .italic()
                }

                Spacer()
            }

            if let dungeon = viewModel.activeDungeon, dungeon.isActive {
                // Active dungeon session
                ActiveDungeonView(dungeon: dungeon, onExit: viewModel.exitDungeon)
            } else {
                // Dungeon selection
                DungeonSelectionView(onStartDungeon: viewModel.startDungeon)
            }
        }
        .padding()
        .systemCard()
    }
}

// MARK: - Active Dungeon View

struct ActiveDungeonView: View {
    let dungeon: Dungeon
    let onExit: () -> Void

    @State private var pulseAnimation = false

    var body: some View {
        VStack(spacing: 32) {
            // Dungeon title
            VStack(spacing: 8) {
                Text("DUNGEON ACTIVE")
                    .font(SystemTypography.mono(14, weight: .bold))
                    .foregroundStyle(SystemTheme.primaryPurple)

                Text(dungeon.title)
                    .font(SystemTypography.titleSmall)
                    .foregroundStyle(SystemTheme.textPrimary)
            }

            // Timer display
            ZStack {
                // Background ring
                Circle()
                    .stroke(SystemTheme.backgroundSecondary, lineWidth: 8)
                    .frame(width: 200, height: 200)

                // Progress ring
                Circle()
                    .trim(from: 0, to: dungeon.progress)
                    .stroke(
                        LinearGradient(
                            colors: [SystemTheme.primaryBlue, SystemTheme.primaryPurple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: dungeon.progress)

                // Time display
                VStack(spacing: 4) {
                    Text(dungeon.formattedTimeRemaining)
                        .font(SystemTypography.timer)
                        .foregroundStyle(SystemTheme.textPrimary)

                    Text("remaining")
                        .font(SystemTypography.caption)
                        .foregroundStyle(SystemTheme.textTertiary)
                }
            }
            .glow(color: SystemTheme.primaryPurple.opacity(pulseAnimation ? 0.5 : 0.2), radius: 20)
            .onAppear {
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    pulseAnimation = true
                }
            }

            // Warning
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(SystemTheme.warningOrange)
                    Text("WARNING")
                        .font(SystemTypography.mono(12, weight: .bold))
                        .foregroundStyle(SystemTheme.warningOrange)
                }

                Text("Leaving the app will cause the raid to FAIL.\nStay focused, Hunter.")
                    .font(SystemTypography.caption)
                    .foregroundStyle(SystemTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Exit button (with penalty warning)
            Button(action: onExit) {
                HStack {
                    Image(systemName: "xmark.circle")
                    Text("ABANDON DUNGEON")
                }
                .font(SystemTypography.mono(14, weight: .semibold))
                .foregroundStyle(SystemTheme.criticalRed)
                .padding()
                .background(SystemTheme.criticalRed.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: SystemRadius.medium))
                .overlay(
                    RoundedRectangle(cornerRadius: SystemRadius.medium)
                        .stroke(SystemTheme.criticalRed.opacity(0.3), lineWidth: 1)
                )
            }
        }
        .padding()
    }
}

// MARK: - Dungeon Selection View

struct DungeonSelectionView: View {
    let onStartDungeon: (Int) -> Void

    private let durations = [15, 25, 45, 60, 90]

    var body: some View {
        VStack(spacing: 20) {
            Text("Select Duration")
                .font(SystemTypography.headline)
                .foregroundStyle(SystemTheme.textSecondary)

            // Duration options
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(durations, id: \.self) { minutes in
                    Button {
                        onStartDungeon(minutes)
                    } label: {
                        VStack(spacing: 8) {
                            Text("\(minutes)")
                                .font(SystemTypography.statMedium)
                                .foregroundStyle(SystemTheme.primaryPurple)

                            Text("minutes")
                                .font(SystemTypography.caption)
                                .foregroundStyle(SystemTheme.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(SystemTheme.backgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: SystemRadius.medium))
                        .overlay(
                            RoundedRectangle(cornerRadius: SystemRadius.medium)
                                .stroke(SystemTheme.primaryPurple.opacity(0.3), lineWidth: 1)
                        )
                    }
                }
            }

            // Info text
            Text("Deep work sessions grant bonus XP and stat increases.\nFocus is power.")
                .font(SystemTypography.caption)
                .foregroundStyle(SystemTheme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
        }
    }
}

// MARK: - Dashboard View Model

@MainActor
class DashboardViewModel: ObservableObject {
    @Published var player: Player
    @Published var dailyQuests: [DailyQuest]
    @Published var bossFights: [BossFight]
    @Published var activeDungeon: Dungeon?

    private var dungeonTimer: Timer?

    init() {
        // Load or create player
        self.player = PlayerDataManager.shared.loadPlayer() ?? Player(name: "Hunter")

        // Load daily quests (use defaults for now)
        self.dailyQuests = DefaultQuests.dailyQuests

        // Load boss fights
        self.bossFights = []

        // Check for active dungeon
        self.activeDungeon = nil
    }

    func completeQuest(_ quest: DailyQuest) {
        guard let index = dailyQuests.firstIndex(where: { $0.id == quest.id }) else { return }

        dailyQuests[index].status = .completed
        dailyQuests[index].currentProgress = 1.0

        // Award rewards
        player.currentXP += quest.xpReward
        player.gold += quest.goldReward
        player.completedQuestCount += 1

        // Check for level up
        checkLevelUp()

        // Update stats
        for statType in quest.targetStats {
            if var stat = player.stats[statType] {
                stat.experience += GameFormulas.statXP(difficulty: quest.difficulty)
                player.stats[statType] = stat
            }
        }

        // Save
        PlayerDataManager.shared.savePlayer(player)
    }

    func dealBossDamage(_ boss: BossFight, _ task: MicroTask) {
        guard let bossIndex = bossFights.firstIndex(where: { $0.id == boss.id }) else { return }
        guard let taskIndex = bossFights[bossIndex].microTasks.firstIndex(where: { $0.id == task.id }) else { return }

        bossFights[bossIndex].microTasks[taskIndex].isCompleted = true
        let result = bossFights[bossIndex].dealDamage(from: task, playerLevel: player.level)

        if result.bossDefeated {
            player.defeatedBossCount += 1
            player.currentXP += boss.xpReward
            player.gold += boss.goldReward
            checkLevelUp()
        }

        PlayerDataManager.shared.savePlayer(player)
    }

    func startDungeon(minutes: Int) {
        activeDungeon = Dungeon(
            title: "Deep Work Session",
            durationMinutes: minutes
        )
        activeDungeon?.start()

        // Start timer
        dungeonTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.handleDungeonTick()
        }
    }

    func exitDungeon() {
        dungeonTimer?.invalidate()
        dungeonTimer = nil

        activeDungeon?.fail()

        // Apply penalty
        player.penaltyCount += 1

        activeDungeon = nil
        PlayerDataManager.shared.savePlayer(player)
    }

    private func completeDungeon() {
        dungeonTimer?.invalidate()
        dungeonTimer = nil

        guard let dungeon = activeDungeon else { return }

        player.currentXP += dungeon.xpReward
        player.gold += dungeon.goldReward
        player.dungeonsClearedCount += 1

        // Award stat XP
        for statType in dungeon.targetStats {
            if var stat = player.stats[statType] {
                stat.experience += GameFormulas.statXP(difficulty: dungeon.difficulty) * 2
                player.stats[statType] = stat
            }
        }

        checkLevelUp()
        activeDungeon = nil
        PlayerDataManager.shared.savePlayer(player)
    }

    private func handleDungeonTick() {
        activeDungeon?.tick()

        if activeDungeon?.isComplete == true {
            completeDungeon()
        }
    }

    private func checkLevelUp() {
        while player.currentXP >= GameFormulas.xpRequired(forLevel: player.level + 1) {
            player.level += 1
            player.title = player.rank.title
        }
    }
}

// MARK: - Preview

#Preview("Dashboard") {
    DashboardView()
}
