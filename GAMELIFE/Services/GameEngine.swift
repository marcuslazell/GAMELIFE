//
//  GameEngine.swift
//  GAMELIFE
//
//  [SYSTEM]: Core processing unit activated.
//  All game logic flows through this nexus.
//

import Foundation
import Combine
import SwiftUI
import CoreLocation
import UIKit

// MARK: - Game Engine

/// The central nervous system of GAMELIFE
/// Manages all game logic, XP calculations, level ups, and rewards
@MainActor
class GameEngine: ObservableObject {

    static let shared = GameEngine()
    private static let defaultQuestMigrationKey = "didMigrateDefaultQuestTemplates"
    private static let zeroStatBaselineMigrationKey = "didMigrateZeroStatBaseline"

    // MARK: - Published Properties

    @Published var player: Player
    @Published var dailyQuests: [DailyQuest] = []
    @Published var activeBossFights: [BossFight] = []
    @Published var activeDungeon: Dungeon?
    @Published var pendingLootBoxes: [LootBox] = []
    @Published var pendingPenalties: [PenaltyQuest] = []
    @Published var recentActivity: [ActivityLogEntry] = []

    // State tracking
    @Published var isInDungeon = false
    @Published var showLevelUpAlert = false
    @Published var lastLevelUpData: LevelUpData?
    @Published var showLootBoxOpening = false
    @Published var currentLootBox: LootBox?
    @Published private(set) var canUndoLatestQuestCompletion = false
    @Published private(set) var lastUndoQuestTitle: String?

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()
    private var dungeonTimer: Timer?
    private var autoSaveTimer: Timer?
    private var cloudSyncTimer: Timer?
    private var questCompletionUndoSnapshot: QuestCompletionUndoSnapshot?
    private var questCompletionUndoTask: Task<Void, Never>?
    private let questCompletionUndoWindow: TimeInterval = 20

    private struct QuestCompletionUndoSnapshot {
        let player: Player
        let dailyQuests: [DailyQuest]
        let activeBossFights: [BossFight]
        let pendingLootBoxes: [LootBox]
        let pendingPenalties: [PenaltyQuest]
        let recentActivity: [ActivityLogEntry]
        let createdAt: Date
        let questTitle: String
    }

    // MARK: - Initialization

    private init() {
        // Load player or create new
        self.player = PlayerDataManager.shared.loadPlayer() ?? Player(name: "Hunter")

        // Load saved quests (fresh installs start with no defaults)
        self.dailyQuests = QuestDataManager.shared.loadDailyQuests() ?? []

        // Load boss fights
        self.activeBossFights = QuestDataManager.shared.loadBossFights() ?? []

        // Load recent activity log
        self.recentActivity = ActivityLogDataManager.shared.loadActivityLog()

        migrateLegacyDefaultQuestTemplatesIfNeeded()
        migrateLegacyStatBaselineIfNeeded()

        // Ensure loaded quests are in the active cycle and integrations are synced.
        migrateDisabledScreenTimeDataIfNeeded()
        refreshQuestCyclesIfNeeded()
        syncBossLinksWithQuests()
        dailyQuests.forEach { NotificationManager.shared.scheduleQuestReminder(for: $0) }

        // Set up auto-save
        setupAutoSave()

        // Set up health data observers
        setupHealthKitObservers()
        if AppFeatureFlags.screenTimeEnabled {
            setupScreenTimeObservers()
        }
        setupLocationQuestObservers()
        QuestManager.shared.synchronizeMonitoring(with: dailyQuests)
        setupCloudKitSync()
        Task { @MainActor [weak self] in
            await self?.syncDynamicBossGoals()
        }
    }

    // MARK: - Quest Completion

    /// Complete a daily quest and award rewards
    func completeQuest(_ quest: DailyQuest, sendSystemNotification: Bool = true) -> QuestCompletionResult {
        guard let index = dailyQuests.firstIndex(where: { $0.id == quest.id }) else {
            return QuestCompletionResult(success: false, message: "Quest not found")
        }

        guard dailyQuests[index].status != .completed else {
            return QuestCompletionResult(success: false, message: "Quest already completed")
        }

        prepareUndoSnapshot(for: quest.title)

        // Mark as completed
        dailyQuests[index].status = .completed
        dailyQuests[index].currentProgress = 1.0
        let completedQuest = dailyQuests[index]

        // Calculate rewards with streak bonus
        let streakMultiplier = GameFormulas.streakMultiplier(streak: player.currentStreak)
        let baseXP = completedQuest.xpReward
        let finalXP = Int(Double(baseXP) * streakMultiplier)
        let gold = completedQuest.goldReward

        // Check for critical success (loot box chance)
        let isCritical = Double.random(in: 0...1) < GameFormulas.criticalSuccessChance
        var lootBox: LootBox?

        if isCritical {
            // Generate loot box based on quest difficulty
            let rarity = determineLootBoxRarity(for: completedQuest.difficulty)
            lootBox = LootBox(rarity: rarity)
            pendingLootBoxes.append(lootBox!)
        }

        // Award XP
        let leveledUp = awardXP(finalXP)

        // Award gold
        player.gold += gold

        // Award stat XP
        for statType in completedQuest.targetStats {
            awardStatXP(statType, amount: GameFormulas.statXP(difficulty: completedQuest.difficulty))
        }

        // Update counters
        player.completedQuestCount += 1
        QuestDataManager.shared.recordCompletedQuest(completedQuest, xpAwarded: finalXP, goldAwarded: gold)
        logActivity(
            type: .questCompleted,
            title: completedQuest.title,
            detail: "+\(finalXP) XP • +\(gold) Gold"
        )

        // Always emit a system notification for completed quests so users get
        // consistent OS-level banners in addition to in-app feedback.
        if sendSystemNotification {
            NotificationManager.shared.sendQuestCompletionNotification(
                questTitle: completedQuest.title,
                xp: finalXP,
                gold: gold
            )
        }

        applyLinkedQuestDamage(for: completedQuest)

        // Check all quests completed for streak
        checkDailyQuestStreak()

        // Save
        save()
        armQuestCompletionUndoWindow(for: completedQuest.title)

        return QuestCompletionResult(
            success: true,
            message: isCritical ? "CRITICAL SUCCESS!" : "Quest Complete!",
            xpAwarded: finalXP,
            goldAwarded: gold,
            statGains: completedQuest.targetStats.map { ($0, GameFormulas.statXP(difficulty: completedQuest.difficulty)) },
            isCritical: isCritical,
            lootBox: lootBox,
            leveledUp: leveledUp ? lastLevelUpData : nil
        )
    }

    @discardableResult
    func undoLastQuestCompletion() -> Bool {
        guard let snapshot = questCompletionUndoSnapshot else { return false }
        guard Date().timeIntervalSince(snapshot.createdAt) <= questCompletionUndoWindow else {
            clearQuestCompletionUndoSnapshot()
            return false
        }

        player = snapshot.player
        dailyQuests = snapshot.dailyQuests
        activeBossFights = snapshot.activeBossFights
        pendingLootBoxes = snapshot.pendingLootBoxes
        pendingPenalties = snapshot.pendingPenalties
        recentActivity = snapshot.recentActivity

        save()
        SystemMessageHelper.showInfo("Undo Applied", "\"\(snapshot.questTitle)\" completion was reverted.")
        clearQuestCompletionUndoSnapshot()
        return true
    }

    // MARK: - Quest Management

    func saveQuest(_ quest: DailyQuest, replacing existingQuestID: UUID? = nil) {
        let previousQuest = existingQuestID.flatMap { questID in
            dailyQuests.first(where: { $0.id == questID })
        }

        if let existingQuestID,
           let index = dailyQuests.firstIndex(where: { $0.id == existingQuestID }) {
            dailyQuests[index] = quest
        } else {
            dailyQuests.append(quest)
        }

        syncBossLink(for: quest)
        if quest.trackingType == .location || previousQuest?.trackingType == .location {
            syncLocationGeofences()
        }
        QuestManager.shared.synchronizeMonitoring(with: dailyQuests)
        NotificationManager.shared.scheduleQuestReminder(for: quest)
        save()
    }

    func deleteQuest(_ questID: UUID) {
        let deletedQuest = dailyQuests.first(where: { $0.id == questID })
        dailyQuests.removeAll { $0.id == questID }

        for index in activeBossFights.indices {
            activeBossFights[index].linkedQuestIDs.removeAll { $0 == questID }
        }

        if deletedQuest?.trackingType == .location {
            LocationManager.shared.removeQuestGeofence(for: questID)
        }
        QuestManager.shared.synchronizeMonitoring(with: dailyQuests)
        NotificationManager.shared.removeQuestReminder(questID: questID)
        save()
    }

    func startFreshProfile(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        player = Player(name: trimmed.isEmpty ? "Hunter" : trimmed)
        dailyQuests = []
        activeBossFights = []
        activeDungeon = nil
        pendingLootBoxes = []
        pendingPenalties = []
        recentActivity = []
        isInDungeon = false

        LocationManager.shared.removeAllGeofences()
        QuestManager.shared.synchronizeMonitoring(with: dailyQuests)
        clearQuestCompletionUndoSnapshot()
        save()
    }

    func resetQuestProgressManually() {
        let now = Date()
        for index in dailyQuests.indices {
            dailyQuests[index].status = .available
            dailyQuests[index].currentProgress = 0
            dailyQuests[index].expiresAt = dailyQuests[index].resolvedFrequency.nextResetDate(from: now)
        }
        save()
    }

    /// Determine loot box rarity based on quest difficulty
    private func determineLootBoxRarity(for difficulty: QuestDifficulty) -> LootBox.LootRarity {
        let roll = Double.random(in: 0...1)

        switch difficulty {
        case .trivial, .easy:
            return .common
        case .normal:
            if roll < 0.1 { return .rare }
            return .common
        case .hard:
            if roll < 0.05 { return .epic }
            if roll < 0.25 { return .rare }
            return .common
        case .extreme:
            if roll < 0.1 { return .epic }
            if roll < 0.4 { return .rare }
            return .common
        case .legendary:
            if roll < 0.05 { return .legendary }
            if roll < 0.2 { return .epic }
            return .rare
        }
    }

    // MARK: - XP System

    /// Award XP to the player, checking for level up
    @discardableResult
    func awardXP(_ amount: Int) -> Bool {
        let previousLevel = player.level
        player.currentXP += amount
        player.totalXP += amount

        // Check for level up(s)
        var leveledUp = false
        while player.currentXP >= GameFormulas.xpRequired(forLevel: player.level + 1) {
            player.level += 1
            leveledUp = true
        }

        if leveledUp {
            handleLevelUp(from: previousLevel, to: player.level)
        }

        return leveledUp
    }

    /// Award XP to a specific stat
    func awardStatXP(_ statType: StatType, amount: Int) {
        guard var stat = player.stats[statType] else { return }

        let sanitizedAmount = max(1, amount)
        let pointGain = max(1, Int((Double(sanitizedAmount) / 5.0).rounded()))

        stat.experience += sanitizedAmount
        stat.baseValue = min(999, stat.baseValue + pointGain)

        player.stats[statType] = stat
    }

    /// Handle level up rewards and notifications
    private func handleLevelUp(from previousLevel: Int, to newLevel: Int) {
        let previousRank = PlayerRank.rank(forLevel: previousLevel)
        let newRank = PlayerRank.rank(forLevel: newLevel)
        let rankUp = newRank != previousRank

        // Update title if rank changed
        if rankUp {
            player.title = newRank.title
            if !player.unlockedTitles.contains(newRank.title) {
                player.unlockedTitles.append(newRank.title)
            }
        }

        // Create level up data for display
        lastLevelUpData = LevelUpData(
            previousLevel: previousLevel,
            newLevel: newLevel,
            previousRank: previousRank,
            newRank: newRank,
            rankUp: rankUp,
            statsUnlocked: [] // Could add stat point allocation here
        )

        showLevelUpAlert = true

        // Send notification
        NotificationManager.shared.sendLevelUpNotification(level: newLevel, rank: newRank)
    }

    // MARK: - Boss Fights

    /// Create a new boss fight (project)
    func createBossFight(
        title: String,
        description: String,
        difficulty: QuestDifficulty,
        targetStats: [StatType],
        maxHP: Int,
        linkedQuestIDs: [UUID] = [],
        dynamicGoal: DynamicBossGoal? = nil,
        autoGenerateGoalQuest: Bool = false,
        deadline: Date?
    ) -> BossFight {
        var boss = BossFight(
            title: title,
            description: description,
            difficulty: difficulty,
            targetStats: targetStats,
            maxHP: maxHP,
            linkedQuestIDs: linkedQuestIDs,
            dynamicGoal: dynamicGoal,
            deadline: deadline
        )

        if autoGenerateGoalQuest, let dynamicGoal {
            let generated = makeGeneratedQuest(for: boss, goal: dynamicGoal)
            dailyQuests.append(generated)
            boss.linkedQuestIDs.append(generated.id)
            boss.dynamicGoal?.generatedQuestID = generated.id
            NotificationManager.shared.scheduleQuestReminder(for: generated)
        }

        activeBossFights.append(boss)
        if boss.dynamicGoal != nil {
            tagDynamicLinkedQuests(for: boss.id, linkedQuestIDs: boss.linkedQuestIDs)
        }
        adjustGeneratedGoalQuestTargets()
        save()

        return boss
    }

    func updateDynamicBossCurrentValue(bossId: UUID, currentValue: Double) {
        guard let index = activeBossFights.firstIndex(where: { $0.id == bossId }) else { return }
        let wasDefeated = activeBossFights[index].isDefeated
        activeBossFights[index].updateDynamicGoalCurrentValue(currentValue)

        if let generatedQuestID = activeBossFights[index].dynamicGoal?.generatedQuestID,
           let questIndex = dailyQuests.firstIndex(where: { $0.id == generatedQuestID }) {
            if dailyQuests[questIndex].trackingType == .manual {
                dailyQuests[questIndex].currentProgress = activeBossFights[index].dynamicGoal?.normalizedProgress ?? 0
                dailyQuests[questIndex].status = dailyQuests[questIndex].currentProgress >= 1 ? .completed : .inProgress
            }
        }

        adjustGeneratedGoalQuestTargets()

        if activeBossFights[index].isDefeated && !wasDefeated {
            let boss = activeBossFights[index]
            handleBossDefeated(boss)
        } else {
            save()
        }
    }

    /// Add a micro-task to a boss fight
    func addMicroTask(to bossId: UUID, title: String, difficulty: QuestDifficulty) {
        guard let index = activeBossFights.firstIndex(where: { $0.id == bossId }) else { return }

        let task = MicroTask(title: title, difficulty: difficulty)
        activeBossFights[index].microTasks.append(task)
        save()
    }

    /// Complete a micro-task and deal damage to boss
    func completeMicroTask(bossId: UUID, taskId: UUID) -> DamageResult? {
        guard let bossIndex = activeBossFights.firstIndex(where: { $0.id == bossId }),
              let taskIndex = activeBossFights[bossIndex].microTasks.firstIndex(where: { $0.id == taskId }) else {
            return nil
        }

        // Mark task as completed
        activeBossFights[bossIndex].microTasks[taskIndex].isCompleted = true

        // Deal damage
        let task = activeBossFights[bossIndex].microTasks[taskIndex]
        let result = activeBossFights[bossIndex].dealDamage(from: task, playerLevel: player.level)

        // Check if boss defeated
        if result.bossDefeated {
            handleBossDefeated(activeBossFights[bossIndex])
        }

        save()
        return result
    }

    /// Deal boss damage from completion of linked daily quests.
    private func applyLinkedQuestDamage(for quest: DailyQuest) {
        var defeatedBossIDs: [UUID] = []

        for index in activeBossFights.indices {
            guard activeBossFights[index].linkedQuestIDs.contains(quest.id),
                  !activeBossFights[index].isDefeated else {
                continue
            }

            let result = activeBossFights[index].dealLinkedQuestDamage(from: quest, playerLevel: player.level)

            if result.bossDefeated {
                defeatedBossIDs.append(activeBossFights[index].id)
            }
        }

        for bossID in defeatedBossIDs {
            if let defeatedBoss = activeBossFights.first(where: { $0.id == bossID }) {
                handleBossDefeated(defeatedBoss)
            }
        }
    }

    /// Handle boss defeat rewards
    private func handleBossDefeated(_ boss: BossFight) {
        // Award XP and gold
        let xp = boss.xpReward
        let gold = boss.goldReward

        awardXP(xp)
        player.gold += gold

        // Award stat XP
        for statType in boss.targetStats {
            awardStatXP(statType, amount: GameFormulas.statXP(difficulty: boss.difficulty) * 5)
        }

        // Increment counter
        player.defeatedBossCount += 1
        logActivity(
            type: .bossDefeated,
            title: boss.title,
            detail: "+\(xp) XP • +\(gold) Gold"
        )

        // Generate epic/legendary loot box
        let lootBox = LootBox(rarity: boss.difficulty == .legendary ? .legendary : .epic)
        pendingLootBoxes.append(lootBox)

        // Remove from active
        activeBossFights.removeAll { $0.id == boss.id }

        if let generatedQuestID = boss.dynamicGoal?.generatedQuestID {
            dailyQuests.removeAll { $0.id == generatedQuestID }
            NotificationManager.shared.removeQuestReminder(questID: generatedQuestID)
        }

        for index in dailyQuests.indices where dailyQuests[index].linkedBossID == boss.id {
            dailyQuests[index].linkedBossID = nil
            if dailyQuests[index].linkedDynamicBossID == boss.id {
                dailyQuests[index].linkedDynamicBossID = nil
            }
        }

        // Send notification
        NotificationManager.shared.sendBossDefeatedNotification(bossName: boss.title)
    }

    // MARK: - Dungeon System

    /// Start a dungeon (deep work session)
    func startDungeon(minutes: Int, title: String = "Deep Work Session") {
        let dungeon = Dungeon(
            title: title,
            durationMinutes: minutes
        )

        activeDungeon = dungeon
        activeDungeon?.start()
        isInDungeon = true

        // Start app blocking if Screen Time is authorized
        if AppFeatureFlags.screenTimeEnabled && ScreenTimeManager.shared.isAuthorized {
            ScreenTimeManager.shared.startDungeonBlocking(
                duration: TimeInterval(minutes * 60)
            )
        }

        // Start timer
        dungeonTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                self?.tickDungeon()
            }
        }

        // Send notification
        NotificationManager.shared.scheduleDungeonEndNotification(in: minutes)
    }

    /// Tick the dungeon timer
    private func tickDungeon() {
        activeDungeon?.tick()

        if activeDungeon?.isComplete == true {
            completeDungeon()
        }
    }

    /// Complete a dungeon successfully
    func completeDungeon() {
        guard let dungeon = activeDungeon else { return }

        dungeonTimer?.invalidate()
        dungeonTimer = nil

        // Award rewards
        let xp = dungeon.xpReward
        let gold = dungeon.goldReward

        awardXP(xp)
        player.gold += gold

        // Award stat XP (intelligence and willpower)
        for statType in dungeon.targetStats {
            awardStatXP(statType, amount: GameFormulas.statXP(difficulty: dungeon.difficulty) * 2)
        }

        // Update counter
        player.dungeonsClearedCount += 1

        // End blocking
        if AppFeatureFlags.screenTimeEnabled {
            ScreenTimeManager.shared.endDungeonBlocking()
        }

        // Clear state
        activeDungeon?.complete()
        isInDungeon = false

        save()

        // Send celebration notification
        NotificationManager.shared.sendDungeonClearedNotification(
            dungeonName: dungeon.title,
            xp: xp
        )
    }

    /// Fail/abandon a dungeon
    func failDungeon() {
        guard activeDungeon != nil else { return }

        dungeonTimer?.invalidate()
        dungeonTimer = nil

        activeDungeon?.fail()

        // End blocking
        if AppFeatureFlags.screenTimeEnabled {
            ScreenTimeManager.shared.endDungeonBlocking()
        }

        // Apply penalty
        applyPenalty(reason: .dungeonFailed)

        // Clear state
        isInDungeon = false
        activeDungeon = nil

        save()
    }

    // MARK: - Loot Box System

    /// Open a loot box and collect rewards
    func openLootBox(_ lootBox: LootBox) -> [LootItem] {
        guard let index = pendingLootBoxes.firstIndex(where: { $0.id == lootBox.id }) else {
            return []
        }

        pendingLootBoxes[index].isOpened = true
        let contents = pendingLootBoxes[index].contents

        // Apply rewards
        for item in contents {
            switch item {
            case .gold(let amount):
                player.gold += amount

            case .bonusXP(let amount):
                awardXP(amount)

            case .shadowSoldier(let name, let rank):
                let soldier = ShadowSoldier(
                    id: UUID(),
                    name: name,
                    rank: rank,
                    obtainedDate: Date(),
                    source: "Loot Box"
                )
                player.shadowSoldiers.append(soldier)

            case .title(let title):
                if !player.unlockedTitles.contains(title) {
                    player.unlockedTitles.append(title)
                }

            case .statBoost(let stat, let amount):
                if var playerStat = player.stats[stat] {
                    playerStat.bonusValue += amount
                    player.stats[stat] = playerStat
                }
            }
        }

        // Remove from pending
        pendingLootBoxes.remove(at: index)

        logActivity(
            type: .rewardConsumed,
            title: "Loot Box Opened",
            detail: "\(contents.count) reward\(contents.count == 1 ? "" : "s") claimed"
        )

        save()
        return contents
    }

    // MARK: - Streak System

    /// Check and update daily quest streak
    private func checkDailyQuestStreak() {
        let dailyCycleQuests = dailyQuests.filter { $0.resolvedFrequency == .daily }
        guard !dailyCycleQuests.isEmpty else { return }

        let completedCount = dailyCycleQuests.filter { $0.status == .completed }.count
        let totalRequired = dailyCycleQuests.count

        // All daily quests completed?
        if completedCount >= totalRequired {
            let today = Calendar.current.startOfDay(for: Date())

            if let lastActive = player.lastActiveDate {
                let lastActiveDay = Calendar.current.startOfDay(for: lastActive)
                let dayDifference = Calendar.current.dateComponents([.day], from: lastActiveDay, to: today).day ?? 0

                if dayDifference == 1 {
                    // Consecutive day - increment streak
                    player.currentStreak += 1
                } else if dayDifference > 1 {
                    // Streak broken
                    player.currentStreak = 1
                }
                // Same day - don't change streak
            } else {
                // First completion ever
                player.currentStreak = 1
            }

            // Update longest streak
            if player.currentStreak > player.longestStreak {
                player.longestStreak = player.currentStreak
            }

            player.lastActiveDate = today
        }
    }

    /// Legacy entrypoint retained for compatibility.
    private func checkForMissedQuests() {
        refreshQuestCyclesIfNeeded()
    }

    /// Rolls quests into the currently active cycle based on frequency.
    private func refreshQuestCyclesIfNeeded(referenceDate: Date = Date()) {
        guard !dailyQuests.isEmpty else { return }

        var didChange = false
        var missedQuestCount = 0
        for index in dailyQuests.indices {
            while referenceDate >= dailyQuests[index].expiresAt {
                if dailyQuests[index].status != .completed {
                    missedQuestCount += 1
                }
                dailyQuests[index].status = .available
                dailyQuests[index].currentProgress = 0
                dailyQuests[index].expiresAt = dailyQuests[index].resolvedFrequency.nextResetDate(from: dailyQuests[index].expiresAt)
                didChange = true
            }
        }

        if missedQuestCount > 0 {
            applyMissedQuestDamage(for: missedQuestCount)
            didChange = true
        }

        if didChange {
            save()
        }
    }

    private func applyMissedQuestDamage(for missedQuestCount: Int) {
        player.currentStreak = 0

        let damage = GameFormulas.penaltyDamage(missedQuests: missedQuestCount)
        player.currentHP = max(0, player.currentHP - damage)

        if player.currentHP == 0 {
            applyPenalty(reason: .missedDailyQuests(count: missedQuestCount))
            player.currentHP = player.maxHP

            SystemMessageHelper.showWarning(
                "HP depleted. You missed \(missedQuestCount) quest\(missedQuestCount == 1 ? "" : "s"), penalty enforced."
            )
        }
    }

    private func syncBossLinksWithQuests() {
        let allQuestIDs = Set(dailyQuests.map(\.id))
        var didChange = false

        for index in activeBossFights.indices {
            let existing = activeBossFights[index].linkedQuestIDs
            let filtered = existing.filter { allQuestIDs.contains($0) }
            if filtered.count != existing.count {
                activeBossFights[index].linkedQuestIDs = filtered
                didChange = true
            }
        }

        if didChange {
            save()
        }
    }

    private func syncBossLink(for quest: DailyQuest) {
        for index in activeBossFights.indices {
            activeBossFights[index].linkedQuestIDs.removeAll { $0 == quest.id }
        }

        if let linkedBossID = quest.linkedBossID,
           let bossIndex = activeBossFights.firstIndex(where: { $0.id == linkedBossID }) {
            activeBossFights[bossIndex].linkedQuestIDs.append(quest.id)
            activeBossFights[bossIndex].linkedQuestIDs = Array(Set(activeBossFights[bossIndex].linkedQuestIDs))
            if activeBossFights[bossIndex].dynamicGoal != nil,
               let questIndex = dailyQuests.firstIndex(where: { $0.id == quest.id }) {
                dailyQuests[questIndex].linkedDynamicBossID = linkedBossID
            }
        }
    }

    private func makeGeneratedQuest(for boss: BossFight, goal: DynamicBossGoal) -> DailyQuest {
        let cadenceTarget = max(0.1, goal.perCadenceTarget)
        let unit = goal.unitLabel
        let title: String
        let description: String
        let trackingType: QuestTrackingType
        let healthKitIdentifier: String?

        switch goal.type {
        case .weight:
            title = "\(boss.title): \(goal.cadence.rawValue) Weight Progress"
            description = "Move at least \(formatGoalAmount(cadenceTarget, unit: unit)) toward your weight goal this \(goal.cadence.rawValue.lowercased())."
            trackingType = .manual
            healthKitIdentifier = nil
        case .bodyFat:
            title = "\(boss.title): \(goal.cadence.rawValue) Body Fat Progress"
            description = "Reduce body fat by \(formatGoalAmount(cadenceTarget, unit: unit)) this \(goal.cadence.rawValue.lowercased())."
            trackingType = .manual
            healthKitIdentifier = nil
        case .savings:
            title = "\(boss.title): \(goal.cadence.rawValue) Savings Deposit"
            description = "Deposit at least \(formatGoalAmount(cadenceTarget, unit: unit)) this \(goal.cadence.rawValue.lowercased()) to damage the savings boss."
            trackingType = .manual
            healthKitIdentifier = nil
        case .workoutConsistency:
            title = "\(boss.title): \(goal.cadence.rawValue) Workout Count"
            description = "Complete at least \(formatGoalAmount(cadenceTarget, unit: unit)) this \(goal.cadence.rawValue.lowercased()) to damage this boss."
            trackingType = .healthKit
            healthKitIdentifier = "HKWorkoutType"
        case .screenTimeDiscipline:
            title = "\(boss.title): \(goal.cadence.rawValue) Screen Discipline"
            description = "Keep social media usage under \(formatGoalAmount(cadenceTarget, unit: unit)) this \(goal.cadence.rawValue.lowercased())."
            trackingType = .manual
            healthKitIdentifier = nil
        }

        return DailyQuest(
            title: title,
            description: description,
            difficulty: boss.difficulty,
            status: .available,
            targetStats: goal.type.defaultStatTargets,
            frequency: goal.cadence.questFrequency,
            trackingType: trackingType,
            currentProgress: 0,
            targetValue: cadenceTarget,
            unit: unit,
            healthKitIdentifier: healthKitIdentifier,
            linkedBossID: boss.id,
            linkedDynamicBossID: boss.id
        )
    }

    private func adjustGeneratedGoalQuestTargets(referenceDate: Date = Date()) {
        var didChange = false

        for bossIndex in activeBossFights.indices {
            guard let goal = activeBossFights[bossIndex].dynamicGoal else {
                continue
            }

            let dynamicLinkedQuestIDs = dynamicLinkedQuestIDs(for: activeBossFights[bossIndex])
            guard !dynamicLinkedQuestIDs.isEmpty else { continue }
            let questCount = max(1, dynamicLinkedQuestIDs.count)
            let adjustedTarget = adjustedCadenceTarget(for: goal, deadline: activeBossFights[bossIndex].deadline, now: referenceDate)
            let perQuestTarget = adjustedTarget / Double(questCount)
            let roundedTarget = max(0.1, (perQuestTarget * 10).rounded() / 10)
            let targetFrequency = goal.cadence.questFrequency

            for questID in dynamicLinkedQuestIDs {
                guard let linkedQuestIndex = dailyQuests.firstIndex(where: { $0.id == questID }) else {
                    continue
                }
                if abs(dailyQuests[linkedQuestIndex].targetValue - roundedTarget) > 0.0001 {
                    dailyQuests[linkedQuestIndex].targetValue = roundedTarget
                    didChange = true
                }
                if dailyQuests[linkedQuestIndex].frequency != targetFrequency {
                    dailyQuests[linkedQuestIndex].frequency = targetFrequency
                    didChange = true
                }
            }
        }

        if didChange {
            save()
        }
    }

    private func dynamicLinkedQuestIDs(for boss: BossFight) -> [UUID] {
        let bossLinkedSet = Set(boss.linkedQuestIDs)
        return dailyQuests
            .filter { quest in
                quest.linkedDynamicBossID == boss.id && bossLinkedSet.contains(quest.id)
            }
            .map(\.id)
    }

    private func tagDynamicLinkedQuests(for bossID: UUID, linkedQuestIDs: [UUID]) {
        let linkedSet = Set(linkedQuestIDs)
        for index in dailyQuests.indices where linkedSet.contains(dailyQuests[index].id) {
            dailyQuests[index].linkedDynamicBossID = bossID
        }
    }

    private func adjustedCadenceTarget(for goal: DynamicBossGoal, deadline: Date?, now: Date) -> Double {
        guard let deadline, deadline > now else {
            return goal.perCadenceTarget
        }

        let periodsLeft: Int = {
            switch goal.cadence {
            case .daily:
                let days = Calendar.current.dateComponents([.day], from: now, to: deadline).day ?? 0
                return max(1, days)
            case .weekly:
                let days = Calendar.current.dateComponents([.day], from: now, to: deadline).day ?? 0
                return max(1, Int(ceil(Double(days) / 7.0)))
            case .monthly:
                let months = Calendar.current.dateComponents([.month], from: now, to: deadline).month ?? 0
                return max(1, months)
            }
        }()

        let dynamicTarget = goal.remainingAmount / Double(periodsLeft)
        return max(goal.perCadenceTarget, dynamicTarget)
    }

    private func formatGoalAmount(_ value: Double, unit: String) -> String {
        if unit == "$" {
            return String(format: "$%.0f", value)
        }
        if value.rounded() == value {
            return "\(Int(value))\(unit)"
        }
        return String(format: "%.1f%@", value, unit)
    }

    private func syncLocationGeofences() {
        let locationManager = LocationManager.shared

        for quest in dailyQuests {
            locationManager.upsertQuestGeofence(for: quest)
        }

        let validQuestIDs = Set(dailyQuests.map(\.id))
        for active in locationManager.activeGeofences {
            guard let questID = active.questID else { continue }
            if !validQuestIDs.contains(questID) {
                locationManager.removeGeofence(for: active)
            }
        }
    }

    private func migrateLegacyDefaultQuestTemplatesIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.defaultQuestMigrationKey) else { return }

        defer {
            defaults.set(true, forKey: Self.defaultQuestMigrationKey)
        }

        guard !dailyQuests.isEmpty else { return }

        let templateTitles = Set(DefaultQuests.dailyQuests.map(\.title))
        let currentTitles = Set(dailyQuests.map(\.title))

        if currentTitles.isSubset(of: templateTitles) {
            dailyQuests = []
        }
    }

    private func migrateLegacyStatBaselineIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.zeroStatBaselineMigrationKey) else { return }

        defer {
            defaults.set(true, forKey: Self.zeroStatBaselineMigrationKey)
        }

        // Only migrate untouched legacy players that still have seed values.
        let isLegacySeededProfile = StatType.allCases.allSatisfy { type in
            guard let stat = player.stats[type] else { return false }
            return stat.baseValue == 10 && stat.bonusValue == 0 && stat.experience == 0
        }

        guard isLegacySeededProfile else { return }

        for type in StatType.allCases {
            guard var stat = player.stats[type] else { continue }
            stat.baseValue = 0
            player.stats[type] = stat
        }
    }

    // MARK: - HealthKit Integration

    private func setupLocationQuestObservers() {
        NotificationCenter.default
            .publisher(for: .locationVisitCompleted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleLocationVisitNotification(notification)
            }
            .store(in: &cancellables)
    }

    private func handleLocationVisitNotification(_ notification: Notification) {
        if let questID = notification.userInfo?["questID"] as? UUID,
           let quest = dailyQuests.first(where: { $0.id == questID && $0.trackingType == .location && $0.status != .completed }) {
            _ = completeQuest(quest)
            return
        }

        guard let visit = notification.userInfo?["visit"] as? LocationVisit else {
            return
        }

        let visitLocation = CLLocation(latitude: visit.location.latitude, longitude: visit.location.longitude)
        if let quest = dailyQuests.first(where: { quest in
            guard quest.trackingType == .location,
                  quest.status != .completed,
                  let coordinate = quest.locationCoordinate else {
                return false
            }

            let questLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            return visitLocation.distance(from: questLocation) <= coordinate.radius
        }) {
            _ = completeQuest(quest)
        }
    }

    /// Set up observers for HealthKit data changes
    private func setupHealthKitObservers() {
        NotificationCenter.default
            .publisher(for: .healthKitDataDidUpdate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.updateHealthKitQuests()
                }
            }
            .store(in: &cancellables)

        // Listen for health data updates
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.updateHealthKitQuests()
            }
        }
    }

    private func setupScreenTimeObservers() {
        NotificationCenter.default
            .publisher(for: .screenTimeDataDidUpdate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.updateScreenTimeQuests()
                }
            }
            .store(in: &cancellables)

        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.updateScreenTimeQuests()
            }
        }
    }

    private func setupCloudKitSync() {
        CloudKitSyncManager.shared.start()

        NotificationCenter.default
            .publisher(for: UIApplication.willEnterForegroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.syncFromCloudIfNeeded()
                }
            }
            .store(in: &cancellables)

        cloudSyncTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.syncFromCloudIfNeeded()
            }
        }

        Task { @MainActor [weak self] in
            await self?.syncFromCloudIfNeeded(force: true)
        }
    }

    private func syncFromCloudIfNeeded(force: Bool = false) async {
        guard let snapshot = await CloudKitSyncManager.shared.fetchLatestSnapshotIfNewer(force: force) else {
            return
        }
        applyCloudSnapshot(snapshot)
    }

    private func applyCloudSnapshot(_ snapshot: CloudGameStateSnapshot) {
        player = snapshot.player
        dailyQuests = snapshot.dailyQuests
        activeBossFights = snapshot.bossFights
        recentActivity = snapshot.recentActivity

        QuestDataManager.shared.overwriteQuestHistory(snapshot.questHistory)
        LocationDataManager.shared.saveLocations(snapshot.trackedLocations)

        refreshQuestCyclesIfNeeded()
        syncBossLinksWithQuests()
        syncLocationGeofences()
        QuestManager.shared.synchronizeMonitoring(with: dailyQuests)

        dailyQuests.forEach { NotificationManager.shared.scheduleQuestReminder(for: $0) }

        save(syncToCloud: false)
        CloudKitSyncManager.shared.markLocalStateApplied(at: snapshot.updatedAt)
        SystemMessageHelper.showInfo("Cloud Sync", "Pulled latest progress from iCloud.")
    }

    private func dynamicGoalCurrentValue(
        for boss: BossFight,
        healthManager: HealthKitManager,
        screenTimeManager: ScreenTimeManager
    ) async -> Double? {
        guard let goal = boss.dynamicGoal else { return nil }

        switch goal.type {
        case .weight:
            guard healthManager.isAuthorized else { return nil }
            return healthManager.currentBodyWeightLB > 0 ? healthManager.currentBodyWeightLB : nil
        case .bodyFat:
            guard healthManager.isAuthorized else { return nil }
            return healthManager.currentBodyFatPercent > 0 ? healthManager.currentBodyFatPercent : nil
        case .savings:
            return goal.currentValue
        case .workoutConsistency:
            guard healthManager.isAuthorized else { return nil }
            let start = cadenceStartDate(for: goal.cadence)
            let workouts = await healthManager.fetchWorkoutCount(from: start, to: Date())
            return Double(workouts)
        case .screenTimeDiscipline:
            guard AppFeatureFlags.screenTimeEnabled else { return nil }
            guard screenTimeManager.isAuthorized else { return nil }
            return Double(max(0, screenTimeManager.socialMediaMinutesToday))
        }
    }

    private func cadenceStartDate(for cadence: GoalCadence, now: Date = Date()) -> Date {
        let calendar = Calendar.current
        switch cadence {
        case .daily:
            return calendar.startOfDay(for: now)
        case .weekly:
            return calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))
                ?? calendar.startOfDay(for: now)
        case .monthly:
            return calendar.date(from: calendar.dateComponents([.year, .month], from: now))
                ?? calendar.startOfDay(for: now)
        }
    }

    private func syncDynamicBossGoals() async {
        let healthManager = HealthKitManager.shared
        let screenTimeManager = ScreenTimeManager.shared
        var didChange = false
        var defeatedBossIDs: [UUID] = []

        let dynamicBossIDs = activeBossFights
            .filter { $0.dynamicGoal != nil }
            .map(\.id)

        for bossID in dynamicBossIDs {
            guard let snapshotIndex = activeBossFights.firstIndex(where: { $0.id == bossID }) else { continue }
            let bossSnapshot = activeBossFights[snapshotIndex]

            guard let currentValue = await dynamicGoalCurrentValue(
                for: bossSnapshot,
                healthManager: healthManager,
                screenTimeManager: screenTimeManager
            ) else {
                continue
            }

            guard let bossIndex = activeBossFights.firstIndex(where: { $0.id == bossID }),
                  activeBossFights[bossIndex].dynamicGoal != nil else { continue }

            let wasDefeated = activeBossFights[bossIndex].isDefeated
            let previousHP = activeBossFights[bossIndex].currentHP

            activeBossFights[bossIndex].updateDynamicGoalCurrentValue(currentValue)

            if activeBossFights[bossIndex].currentHP != previousHP {
                didChange = true
            }

            if let generatedQuestID = activeBossFights[bossIndex].dynamicGoal?.generatedQuestID,
               let questIndex = dailyQuests.firstIndex(where: { $0.id == generatedQuestID }),
               dailyQuests[questIndex].trackingType == .manual {
                let progress = activeBossFights[bossIndex].dynamicGoal?.normalizedProgress ?? 0
                dailyQuests[questIndex].currentProgress = progress
                dailyQuests[questIndex].status = progress >= 1 ? .completed : .inProgress
                didChange = true
            }

            if activeBossFights[bossIndex].isDefeated && !wasDefeated {
                defeatedBossIDs.append(activeBossFights[bossIndex].id)
            }
        }

        adjustGeneratedGoalQuestTargets()

        for bossID in defeatedBossIDs {
            if let defeatedBoss = activeBossFights.first(where: { $0.id == bossID }) {
                handleBossDefeated(defeatedBoss)
            }
        }

        if didChange {
            save()
        }
    }

    func updateScreenTimeQuests() async {
        guard AppFeatureFlags.screenTimeEnabled else { return }
        let screenTimeManager = ScreenTimeManager.shared
        var autoCompletedRewards: [(title: String, xp: Int, gold: Int)] = []
        QuestManager.shared.checkExtensionCompletions()
        let extensionProgress = QuestManager.shared.getProgressFromExtension()

        let screenTimeQuestIDs = dailyQuests
            .filter { $0.trackingType == .screenTime }
            .map(\.id)

        for questID in screenTimeQuestIDs {
            guard let questIndex = dailyQuests.firstIndex(where: { $0.id == questID }) else { continue }
            let questSnapshot = dailyQuests[questIndex]

            let reportedProgress = extensionProgress[questID] ?? 0
            let sampledProgress = screenTimeManager.checkQuestProgress(for: questSnapshot)
            let progress = max(reportedProgress, sampledProgress)

            guard let latestIndex = dailyQuests.firstIndex(where: { $0.id == questID }) else { continue }

            dailyQuests[latestIndex].currentProgress = min(progress, 1.0)

            if progress >= 1.0 && dailyQuests[latestIndex].status != .completed {
                let completedTitle = dailyQuests[latestIndex].title
                let completionResult = completeQuest(dailyQuests[latestIndex])
                if completionResult.success {
                    autoCompletedRewards.append((
                        title: completedTitle,
                        xp: completionResult.xpAwarded,
                        gold: completionResult.goldAwarded
                    ))
                }
            }
        }

        if let extensionLog = QuestManager.shared.latestExtensionLog() {
            screenTimeManager.lastDetectedEvent = extensionLog
            screenTimeManager.lastSyncDate = Date()
        }

        for reward in autoCompletedRewards {
            SystemMessageHelper.showQuestComplete(
                title: reward.title,
                xp: reward.xp,
                gold: reward.gold
            )
        }

        await syncDynamicBossGoals()
    }

    private func migrateDisabledScreenTimeDataIfNeeded() {
        guard !AppFeatureFlags.screenTimeEnabled else { return }

        var didMutate = false

        for index in dailyQuests.indices where dailyQuests[index].trackingType == .screenTime {
            let quest = dailyQuests[index]
            dailyQuests[index] = DailyQuest(
                id: quest.id,
                title: quest.title,
                description: quest.description,
                difficulty: quest.difficulty,
                status: quest.status,
                targetStats: quest.targetStats,
                frequency: quest.frequency,
                trackingType: .manual,
                currentProgress: quest.currentProgress,
                targetValue: quest.targetValue,
                unit: quest.unit,
                createdAt: quest.createdAt,
                expiresAt: quest.expiresAt,
                healthKitIdentifier: nil,
                screenTimeCategory: nil,
                screenTimeSelectionData: nil,
                locationCoordinate: quest.locationCoordinate,
                locationAddress: quest.locationAddress,
                linkedBossID: quest.linkedBossID,
                linkedDynamicBossID: quest.linkedDynamicBossID,
                reminderEnabled: quest.reminderEnabled,
                reminderTime: quest.reminderTime
            )
            didMutate = true
        }

        for index in activeBossFights.indices {
            if activeBossFights[index].dynamicGoal?.type == .screenTimeDiscipline {
                activeBossFights[index].dynamicGoal = nil
                didMutate = true
            }
        }

        if didMutate {
            QuestManager.shared.synchronizeMonitoring(with: dailyQuests)
            save()
        }
    }

    /// Update quest progress from HealthKit
    func updateHealthKitQuests() async {
        let healthManager = HealthKitManager.shared
        var autoCompletedRewards: [(title: String, xp: Int, gold: Int)] = []

        let healthKitQuestIDs = dailyQuests
            .filter { $0.trackingType == .healthKit }
            .map(\.id)

        for questID in healthKitQuestIDs {
            guard let questIndex = dailyQuests.firstIndex(where: { $0.id == questID }) else { continue }
            let questSnapshot = dailyQuests[questIndex]

            let progress = await healthManager.checkQuestProgress(for: questSnapshot)

            guard let latestIndex = dailyQuests.firstIndex(where: { $0.id == questID }) else { continue }
            dailyQuests[latestIndex].currentProgress = min(progress, 1.0)

            // Auto-complete if 100%
            if progress >= 1.0 && dailyQuests[latestIndex].status != .completed {
                let completedTitle = dailyQuests[latestIndex].title
                let completionResult = completeQuest(dailyQuests[latestIndex])
                if completionResult.success {
                    autoCompletedRewards.append((
                        title: completedTitle,
                        xp: completionResult.xpAwarded,
                        gold: completionResult.goldAwarded
                    ))
                }
            }
        }

        for reward in autoCompletedRewards {
            SystemMessageHelper.showQuestComplete(
                title: reward.title,
                xp: reward.xp,
                gold: reward.gold
            )
        }

        await syncDynamicBossGoals()
    }

    // MARK: - Saving

    /// Set up auto-save timer
    private func setupAutoSave() {
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshQuestCyclesIfNeeded()
                self?.adjustGeneratedGoalQuestTargets()
                self?.save()
            }
        }
    }

    /// Save all game data
    func save(syncToCloud: Bool = true) {
        PlayerDataManager.shared.savePlayer(player)
        QuestDataManager.shared.saveDailyQuests(dailyQuests)
        QuestDataManager.shared.saveBossFights(activeBossFights)
        ActivityLogDataManager.shared.saveActivityLog(recentActivity)
        QuestManager.shared.synchronizeMonitoring(with: dailyQuests)
        if syncToCloud {
            CloudKitSyncManager.shared.queueUpload(
                player: player,
                dailyQuests: dailyQuests,
                bossFights: activeBossFights,
                recentActivity: recentActivity
            )
        }
        WatchConnectivityManager.shared.publishSnapshot(
            player: player,
            quests: dailyQuests,
            activities: recentActivity
        )
    }

    func recordExternalActivity(type: ActivityLogType, title: String, detail: String) {
        logActivity(type: type, title: title, detail: detail)
        save()
    }

    private func logActivity(type: ActivityLogType, title: String, detail: String) {
        let entry = ActivityLogEntry(type: type, title: title, detail: detail)
        recentActivity.insert(entry, at: 0)

        if recentActivity.count > 100 {
            recentActivity = Array(recentActivity.prefix(100))
        }
    }

    private func prepareUndoSnapshot(for questTitle: String) {
        questCompletionUndoTask?.cancel()
        questCompletionUndoSnapshot = QuestCompletionUndoSnapshot(
            player: player,
            dailyQuests: dailyQuests,
            activeBossFights: activeBossFights,
            pendingLootBoxes: pendingLootBoxes,
            pendingPenalties: pendingPenalties,
            recentActivity: recentActivity,
            createdAt: Date(),
            questTitle: questTitle
        )
        canUndoLatestQuestCompletion = true
        lastUndoQuestTitle = questTitle
    }

    private func armQuestCompletionUndoWindow(for questTitle: String) {
        canUndoLatestQuestCompletion = true
        lastUndoQuestTitle = questTitle

        questCompletionUndoTask?.cancel()
        questCompletionUndoTask = Task { [weak self] in
            guard let self else { return }
            let delay = UInt64(self.questCompletionUndoWindow * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            await MainActor.run {
                self.clearQuestCompletionUndoSnapshot()
            }
        }
    }

    private func clearQuestCompletionUndoSnapshot() {
        questCompletionUndoTask?.cancel()
        questCompletionUndoTask = nil
        questCompletionUndoSnapshot = nil
        canUndoLatestQuestCompletion = false
        lastUndoQuestTitle = nil
    }

}

// MARK: - Quest Completion Result

struct QuestCompletionResult {
    let success: Bool
    let message: String
    var xpAwarded: Int = 0
    var goldAwarded: Int = 0
    var statGains: [(StatType, Int)] = []
    var isCritical: Bool = false
    var lootBox: LootBox?
    var leveledUp: LevelUpData?
}

// MARK: - Level Up Data

struct LevelUpData {
    let previousLevel: Int
    let newLevel: Int
    let previousRank: PlayerRank
    let newRank: PlayerRank
    let rankUp: Bool
    let statsUnlocked: [StatType]
}

// MARK: - Penalty Reason

enum PenaltyReason {
    case missedDailyQuests(count: Int)
    case dungeonFailed
    case streakBroken
    case custom(String)

    var description: String {
        switch self {
        case .missedDailyQuests(let count):
            return "Failed to complete \(count) daily quest\(count == 1 ? "" : "s")"
        case .dungeonFailed:
            return "Abandoned dungeon before completion"
        case .streakBroken:
            return "Daily streak broken"
        case .custom(let reason):
            return reason
        }
    }
}
