//
//  QuestModels.swift
//  GAMELIFE
//
//  [SYSTEM]: Quest data structures initialized.
//  Your missions await, Hunter.
//

import Foundation
import SwiftUI

// MARK: - Quest Type

/// The three pillars of the quest system
enum QuestType: String, Codable, CaseIterable {
    case daily = "Daily Quest"
    case boss = "Boss Fight"
    case dungeon = "Dungeon"

    var icon: String {
        switch self {
        case .daily: return "list.bullet.rectangle"
        case .boss: return "bolt.shield.fill"
        case .dungeon: return "door.left.hand.closed"
        }
    }

    var description: String {
        switch self {
        case .daily: return "The Preparation to Become Powerful"
        case .boss: return "Defeat the monster blocking your path"
        case .dungeon: return "Enter the realm of deep focus"
        }
    }
}

// MARK: - Quest Status

enum QuestStatus: String, Codable {
    case available = "Available"
    case inProgress = "In Progress"
    case completed = "Completed"
    case failed = "Failed"
    case expired = "Expired"
}

// MARK: - Quest Tracking Type

/// How the quest progress is tracked
enum QuestTrackingType: String, Codable {
    case manual           // User manually marks complete
    case healthKit        // Auto-tracked via HealthKit
    case screenTime       // Auto-tracked via Screen Time API
    case location         // Auto-tracked via Core Location
    case timer            // Tracked by in-app timer (dungeons)

    var icon: String {
        switch self {
        case .manual: return "hand.tap"
        case .healthKit: return "heart.fill"
        case .screenTime: return "iphone"
        case .location: return "location.fill"
        case .timer: return "timer"
        }
    }

    var isAutomatic: Bool {
        self != .manual
    }
}

// MARK: - Quest Frequency

/// How often a quest should reset and become available again.
enum QuestFrequency: String, Codable, CaseIterable, Identifiable {
    case hourly = "Hourly"
    case daily = "Daily"
    case semiWeekly = "Semi-Weekly"
    case weekly = "Weekly"
    case monthly = "Monthly"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .hourly: return "clock"
        case .daily: return "sun.max"
        case .semiWeekly: return "calendar.badge.clock"
        case .weekly: return "calendar"
        case .monthly: return "calendar.circle"
        }
    }

    func nextResetDate(from date: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .hourly:
            let currentHour = calendar.dateInterval(of: .hour, for: date)?.start ?? date
            return calendar.date(byAdding: .hour, value: 1, to: currentHour) ?? date.addingTimeInterval(3600)
        case .daily:
            let startOfDay = calendar.startOfDay(for: date)
            return calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? date.addingTimeInterval(86400)
        case .semiWeekly:
            let startOfDay = calendar.startOfDay(for: date)
            return calendar.date(byAdding: .day, value: 3, to: startOfDay) ?? date.addingTimeInterval(3 * 86400)
        case .weekly:
            let startOfDay = calendar.startOfDay(for: date)
            return calendar.date(byAdding: .day, value: 7, to: startOfDay) ?? date.addingTimeInterval(7 * 86400)
        case .monthly:
            let startOfDay = calendar.startOfDay(for: date)
            return calendar.date(byAdding: .month, value: 1, to: startOfDay) ?? date.addingTimeInterval(30 * 86400)
        }
    }
}

// MARK: - Dynamic Boss Goals

/// Cadence for dynamic goal contribution targets.
enum GoalCadence: String, Codable, CaseIterable, Identifiable {
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .daily: return "sun.max"
        case .weekly: return "calendar"
        case .monthly: return "calendar.circle"
        }
    }

    var questFrequency: QuestFrequency {
        switch self {
        case .daily: return .daily
        case .weekly: return .weekly
        case .monthly: return .monthly
        }
    }
}

enum DynamicBossGoalType: String, Codable, CaseIterable, Identifiable {
    case weight = "Weight Goal"
    case bodyFat = "Body Fat Goal"
    case savings = "Savings Goal"
    case workoutConsistency = "Workout Consistency"
    case screenTimeDiscipline = "Screen-Time Discipline"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .weight: return "scalemass.fill"
        case .bodyFat: return "figure.core.training"
        case .savings: return "banknote.fill"
        case .workoutConsistency: return "figure.run"
        case .screenTimeDiscipline: return "hourglass"
        }
    }

    var defaultStatTargets: [StatType] {
        switch self {
        case .weight: return [.vitality, .strength]
        case .bodyFat: return [.vitality, .willpower]
        case .savings: return [.intelligence, .willpower]
        case .workoutConsistency: return [.strength, .vitality, .willpower]
        case .screenTimeDiscipline: return [.willpower, .spirit]
        }
    }

    var unitLabel: String {
        switch self {
        case .weight: return "lb"
        case .bodyFat: return "%"
        case .savings: return "$"
        case .workoutConsistency: return "workouts"
        case .screenTimeDiscipline: return "minutes"
        }
    }

    var isHealthKitDriven: Bool {
        self == .weight || self == .bodyFat || self == .workoutConsistency
    }

    var isScreenTimeDriven: Bool {
        self == .screenTimeDiscipline
    }
}

struct DynamicBossGoal: Codable {
    var type: DynamicBossGoalType
    var startValue: Double
    var targetValue: Double
    var currentValue: Double
    var cadence: GoalCadence
    var perCadenceTarget: Double
    var generatedQuestID: UUID?
    var lastUpdatedAt: Date?

    var unitLabel: String { type.unitLabel }

    /// Generic normalized goal progress for increasing or decreasing goals.
    var normalizedProgress: Double {
        let delta = targetValue - startValue
        guard abs(delta) > 0.000_001 else {
            return currentValue == targetValue ? 1 : 0
        }
        return min(1, max(0, (currentValue - startValue) / delta))
    }

    var remainingAmount: Double {
        let raw = targetValue - currentValue
        // Match directionality (decreasing goals report positive remaining amount).
        if targetValue < startValue {
            return max(0, currentValue - targetValue)
        }
        return max(0, raw)
    }
}

// MARK: - Base Quest Protocol

protocol QuestProtocol: Identifiable, Codable {
    var id: UUID { get }
    var title: String { get }
    var description: String { get }
    var questType: QuestType { get }
    var difficulty: QuestDifficulty { get }
    var status: QuestStatus { get set }
    var targetStats: [StatType] { get }
    var xpReward: Int { get }
    var goldReward: Int { get }
    var createdAt: Date { get }
}

// MARK: - Daily Quest

/// Daily Quests - "The Preparation to Become Powerful"
/// Following the "Insultingly Low Bar" philosophy
struct DailyQuest: QuestProtocol {
    let id: UUID
    let title: String
    let description: String
    var questType: QuestType = .daily
    let difficulty: QuestDifficulty
    var status: QuestStatus
    let targetStats: [StatType]
    let xpReward: Int
    let goldReward: Int
    let createdAt: Date

    // Daily Quest Specific
    var frequency: QuestFrequency?
    let trackingType: QuestTrackingType
    var currentProgress: Double  // 0.0 to 1.0
    var targetValue: Double      // Target for completion
    let unit: String             // "pushups", "steps", "minutes", etc.
    var expiresAt: Date          // Next time the quest should reset

    // Auto-tracking metadata
    var healthKitIdentifier: String?
    var screenTimeCategory: String?
    var screenTimeSelectionData: Data?
    var locationCoordinate: LocationCoordinate?
    var locationAddress: String?
    var linkedBossID: UUID?
    var linkedDynamicBossID: UUID?
    var reminderEnabled: Bool
    var reminderTime: Date?

    var isExpired: Bool {
        Date() > expiresAt
    }

    var resolvedFrequency: QuestFrequency {
        frequency ?? .daily
    }

    var progressPercentage: Int {
        Int(currentProgress * 100)
    }

    var displayProgress: String {
        let current = Int(currentProgress * targetValue)
        let target = Int(targetValue)
        return "\(current)/\(target) \(unit)"
    }

    /// Metric goals are quests where incremental progress makes sense to render.
    var isMetricGoal: Bool {
        trackingType.isAutomatic || targetValue > 1
    }

    /// UI-safe normalized progress value for inline bars.
    var normalizedProgress: Double {
        if status == .completed { return 1.0 }
        return min(1.0, max(0.0, currentProgress))
    }

    init(
        id: UUID = UUID(),
        title: String,
        description: String,
        difficulty: QuestDifficulty = .easy,
        status: QuestStatus = .available,
        targetStats: [StatType],
        frequency: QuestFrequency? = nil,
        trackingType: QuestTrackingType = .manual,
        currentProgress: Double = 0.0,
        targetValue: Double = 1.0,
        unit: String = "times",
        createdAt: Date = Date(),
        expiresAt: Date? = nil,
        healthKitIdentifier: String? = nil,
        screenTimeCategory: String? = nil,
        screenTimeSelectionData: Data? = nil,
        locationCoordinate: LocationCoordinate? = nil,
        locationAddress: String? = nil,
        linkedBossID: UUID? = nil,
        linkedDynamicBossID: UUID? = nil,
        reminderEnabled: Bool = false,
        reminderTime: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.difficulty = difficulty
        self.status = status
        self.targetStats = targetStats
        self.xpReward = GameFormulas.questXP(difficulty: difficulty)
        self.goldReward = GameFormulas.questGold(difficulty: difficulty)
        self.createdAt = createdAt

        self.frequency = frequency
        self.trackingType = trackingType
        self.currentProgress = min(1.0, max(0.0, currentProgress))
        self.targetValue = targetValue
        self.unit = unit

        // Set expiry by quest frequency (defaults to daily for legacy quests)
        self.expiresAt = expiresAt ?? (frequency ?? .daily).nextResetDate(from: createdAt)

        self.healthKitIdentifier = healthKitIdentifier
        self.screenTimeCategory = screenTimeCategory
        self.screenTimeSelectionData = screenTimeSelectionData
        self.locationCoordinate = locationCoordinate
        self.locationAddress = locationAddress
        self.linkedBossID = linkedBossID
        self.linkedDynamicBossID = linkedDynamicBossID
        self.reminderEnabled = reminderEnabled
        self.reminderTime = reminderTime
    }
}

// MARK: - Location Coordinate (for geo-fencing)

struct LocationCoordinate: Codable {
    let latitude: Double
    let longitude: Double
    let radius: Double // in meters
    let locationName: String
}

// MARK: - Boss Fight (Project)

/// Boss Fights - Large goals with massive HP bars
/// Users deal "damage" by completing micro-tasks
struct BossFight: QuestProtocol {
    let id: UUID
    let title: String        // "The Dragon of Procrastination"
    let description: String  // "Write your book"
    var questType: QuestType = .boss
    let difficulty: QuestDifficulty
    var status: QuestStatus
    let targetStats: [StatType]
    let xpReward: Int
    let goldReward: Int
    let createdAt: Date

    // Boss Specific
    let maxHP: Int
    var currentHP: Int
    var microTasks: [MicroTask]
    var linkedQuestIDs: [UUID] = []
    var dynamicGoal: DynamicBossGoal?
    let deadline: Date?
    var lastDamageDealt: Int
    var totalDamageDealt: Int

    var hpPercentage: Double {
        Double(currentHP) / Double(maxHP)
    }

    var isDefeated: Bool {
        currentHP <= 0
    }

    var remainingHP: Int {
        max(0, currentHP)
    }

    var damageDealtPercentage: Double {
        1.0 - hpPercentage
    }

    init(
        title: String,
        description: String,
        difficulty: QuestDifficulty = .hard,
        targetStats: [StatType],
        maxHP: Int = 10000,
        linkedQuestIDs: [UUID] = [],
        dynamicGoal: DynamicBossGoal? = nil,
        deadline: Date? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.description = description
        self.difficulty = difficulty
        self.status = .available
        self.targetStats = targetStats
        self.xpReward = GameFormulas.questXP(difficulty: difficulty) * 10 // Boss rewards are 10x
        self.goldReward = GameFormulas.questGold(difficulty: difficulty) * 10
        self.createdAt = Date()

        self.maxHP = maxHP
        self.currentHP = maxHP
        self.microTasks = []
        self.linkedQuestIDs = linkedQuestIDs
        self.dynamicGoal = dynamicGoal
        self.deadline = deadline
        self.lastDamageDealt = 0
        self.totalDamageDealt = 0

        if let dynamicGoal {
            // Dynamic bosses derive HP from current metric progress.
            let hp = Int((1.0 - dynamicGoal.normalizedProgress) * Double(maxHP))
            self.currentHP = max(0, min(maxHP, hp))
            if self.currentHP == 0 {
                self.status = .completed
            }
        }
    }

    /// Deal damage to the boss by completing a micro-task
    mutating func dealDamage(from task: MicroTask, playerLevel: Int) -> DamageResult {
        let damage = GameFormulas.bossDamage(taskDifficulty: task.difficulty, playerLevel: playerLevel)
        let isCritical = Double.random(in: 0...1) < GameFormulas.criticalSuccessChance
        let finalDamage = isCritical ? damage * 2 : damage

        return applyDamage(finalDamage, isCritical: isCritical)
    }

    /// Deal damage when a linked quest is completed.
    mutating func dealLinkedQuestDamage(from quest: DailyQuest, playerLevel: Int) -> DamageResult {
        let baseDamage = GameFormulas.bossDamage(taskDifficulty: quest.difficulty, playerLevel: playerLevel)
        let questDamage = max(1, Int(Double(baseDamage) * 0.8))
        return applyDamage(questDamage, isCritical: false)
    }

    private mutating func applyDamage(_ amount: Int, isCritical: Bool) -> DamageResult {
        currentHP -= amount
        lastDamageDealt = amount
        totalDamageDealt += amount

        if currentHP <= 0 {
            currentHP = 0
            status = .completed
        }

        return DamageResult(
            damage: amount,
            isCritical: isCritical,
            bossDefeated: isDefeated
        )
    }

    mutating func updateDynamicGoalCurrentValue(_ newValue: Double, at date: Date = Date()) {
        guard var goal = dynamicGoal else { return }

        goal.currentValue = newValue
        goal.lastUpdatedAt = date
        dynamicGoal = goal

        currentHP = Int((1.0 - goal.normalizedProgress) * Double(maxHP))
        currentHP = max(0, min(maxHP, currentHP))

        if currentHP <= 0 {
            currentHP = 0
            status = .completed
        } else {
            status = .inProgress
        }
    }
}

/// Result of dealing damage to a boss
struct DamageResult {
    let damage: Int
    let isCritical: Bool
    let bossDefeated: Bool
}

/// Micro-tasks that deal damage to bosses
struct MicroTask: Codable, Identifiable {
    let id: UUID
    let title: String
    let difficulty: QuestDifficulty
    var isCompleted: Bool
    let createdAt: Date

    var estimatedDamage: Int {
        GameFormulas.questXP(difficulty: difficulty)
    }

    init(title: String, difficulty: QuestDifficulty = .normal) {
        self.id = UUID()
        self.title = title
        self.difficulty = difficulty
        self.isCompleted = false
        self.createdAt = Date()
    }
}

// MARK: - Dungeon (Deep Work Session)

/// Dungeons - Timed deep work sessions with penalties for early exit
struct Dungeon: QuestProtocol {
    let id: UUID
    let title: String
    let description: String
    var questType: QuestType = .dungeon
    let difficulty: QuestDifficulty
    var status: QuestStatus
    let targetStats: [StatType]
    let xpReward: Int
    let goldReward: Int
    let createdAt: Date

    // Dungeon Specific
    let durationMinutes: Int
    var elapsedSeconds: Int
    var isActive: Bool
    var startedAt: Date?
    var completedAt: Date?
    var raidFailed: Bool

    var totalSeconds: Int {
        durationMinutes * 60
    }

    var remainingSeconds: Int {
        max(0, totalSeconds - elapsedSeconds)
    }

    var progress: Double {
        Double(elapsedSeconds) / Double(totalSeconds)
    }

    var isComplete: Bool {
        elapsedSeconds >= totalSeconds
    }

    var formattedTimeRemaining: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var formattedElapsedTime: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    init(
        title: String,
        description: String = "Focus. The shadows await.",
        difficulty: QuestDifficulty = .normal,
        targetStats: [StatType] = [.intelligence, .willpower],
        durationMinutes: Int = 25
    ) {
        self.id = UUID()
        self.title = title
        self.description = description
        self.difficulty = difficulty
        self.status = .available
        self.targetStats = targetStats
        // Dungeon XP scales with duration
        self.xpReward = (durationMinutes / 5) * GameFormulas.questXP(difficulty: difficulty)
        self.goldReward = (durationMinutes / 5) * GameFormulas.questGold(difficulty: difficulty)
        self.createdAt = Date()

        self.durationMinutes = durationMinutes
        self.elapsedSeconds = 0
        self.isActive = false
        self.startedAt = nil
        self.completedAt = nil
        self.raidFailed = false
    }

    mutating func start() {
        isActive = true
        status = .inProgress
        startedAt = Date()
    }

    mutating func tick() {
        if isActive && !isComplete {
            elapsedSeconds += 1
            if isComplete {
                complete()
            }
        }
    }

    mutating func complete() {
        isActive = false
        status = .completed
        completedAt = Date()
    }

    mutating func fail() {
        isActive = false
        status = .failed
        raidFailed = true
        completedAt = Date()
    }
}

// MARK: - Penalty Quest

/// Penalty Quests - The price of failure
struct PenaltyQuest: Codable, Identifiable {
    let id: UUID
    let title: String
    let description: String
    let penaltyType: PenaltyType
    var isCompleted: Bool
    let createdAt: Date
    let expiresAt: Date

    var isExpired: Bool {
        Date() > expiresAt
    }

    enum PenaltyType: String, Codable {
        case physical = "Physical Punishment"
        case social = "Public Accountability"
        case restriction = "Privilege Restriction"

        var icon: String {
            switch self {
            case .physical: return "figure.core.training"
            case .social: return "megaphone.fill"
            case .restriction: return "lock.fill"
            }
        }
    }

    init(
        title: String,
        description: String,
        penaltyType: PenaltyType,
        hoursToComplete: Int = 24
    ) {
        self.id = UUID()
        self.title = title
        self.description = description
        self.penaltyType = penaltyType
        self.isCompleted = false
        self.createdAt = Date()
        self.expiresAt = Date().addingTimeInterval(TimeInterval(hoursToComplete * 3600))
    }
}

// MARK: - Loot Box

/// Loot Boxes - Variable rewards for critical successes
struct LootBox: Codable, Identifiable {
    let id: UUID
    let rarity: LootRarity
    let contents: [LootItem]
    var isOpened: Bool
    let obtainedAt: Date

    enum LootRarity: String, Codable {
        case common = "Common"
        case rare = "Rare"
        case epic = "Epic"
        case legendary = "Legendary"

        var color: Color {
            switch self {
            case .common: return .gray
            case .rare: return .blue
            case .epic: return .purple
            case .legendary: return .yellow
            }
        }

        var glowIntensity: Double {
            switch self {
            case .common: return 0.3
            case .rare: return 0.5
            case .epic: return 0.7
            case .legendary: return 1.0
            }
        }
    }

    init(rarity: LootRarity) {
        self.id = UUID()
        self.rarity = rarity
        self.contents = LootBox.generateContents(for: rarity)
        self.isOpened = false
        self.obtainedAt = Date()
    }

    static func generateContents(for rarity: LootRarity) -> [LootItem] {
        var items: [LootItem] = []

        // Gold reward based on rarity
        let goldAmount: Int
        switch rarity {
        case .common: goldAmount = Int.random(in: 10...25)
        case .rare: goldAmount = Int.random(in: 25...75)
        case .epic: goldAmount = Int.random(in: 75...200)
        case .legendary: goldAmount = Int.random(in: 200...500)
        }
        items.append(.gold(goldAmount))

        // Chance for bonus XP
        if Double.random(in: 0...1) < 0.3 {
            let xpAmount = goldAmount * 2
            items.append(.bonusXP(xpAmount))
        }

        // Chance for Shadow Soldier (Epic and Legendary only)
        if rarity == .epic || rarity == .legendary {
            if Double.random(in: 0...1) < (rarity == .legendary ? 0.5 : 0.2) {
                let soldierRank: ShadowSoldier.SoldierRank = rarity == .legendary ? .knight : .elite
                items.append(.shadowSoldier(name: generateSoldierName(), rank: soldierRank))
            }
        }

        return items
    }

    static func generateSoldierName() -> String {
        let prefixes = ["Iron", "Shadow", "Dark", "Storm", "Frost", "Flame", "Steel", "Night"]
        let suffixes = ["Fang", "Claw", "Knight", "Guard", "Warden", "Sentinel", "Warrior", "Hunter"]
        let prefix = prefixes.randomElement() ?? "Shadow"
        let suffix = suffixes.randomElement() ?? "Hunter"
        return "\(prefix) \(suffix)"
    }
}

/// Contents of a loot box
enum LootItem: Codable {
    case gold(Int)
    case bonusXP(Int)
    case shadowSoldier(name: String, rank: ShadowSoldier.SoldierRank)
    case title(String)
    case statBoost(stat: StatType, amount: Int)

    var displayName: String {
        switch self {
        case .gold(let amount): return "\(amount) Gold"
        case .bonusXP(let amount): return "\(amount) Bonus XP"
        case .shadowSoldier(let name, _): return "Shadow Soldier: \(name)"
        case .title(let title): return "Title: \(title)"
        case .statBoost(let stat, let amount): return "+\(amount) \(stat.rawValue)"
        }
    }

    var icon: String {
        switch self {
        case .gold: return "dollarsign.circle.fill"
        case .bonusXP: return "star.fill"
        case .shadowSoldier: return "person.fill"
        case .title: return "text.badge.star"
        case .statBoost: return "arrow.up.circle.fill"
        }
    }
}

// MARK: - Default Daily Quests

/// Pre-configured daily quests following the "Insultingly Low Bar" philosophy
struct DefaultQuests {

    static let dailyQuests: [DailyQuest] = [
        // STR - Strength
        DailyQuest(
            title: "1 Pushup",
            description: "Just one. That's all the System asks.",
            difficulty: .trivial,
            targetStats: [.strength],
            trackingType: .manual,
            targetValue: 1,
            unit: "pushup"
        ),
        DailyQuest(
            title: "Walk 10,000 Steps",
            description: "Move your vessel through the world.",
            difficulty: .normal,
            targetStats: [.strength, .vitality],
            trackingType: .healthKit,
            targetValue: 10000,
            unit: "steps",
            healthKitIdentifier: "HKQuantityTypeIdentifierStepCount"
        ),

        // INT - Intelligence
        DailyQuest(
            title: "Read 1 Page",
            description: "A single page. Knowledge compounds.",
            difficulty: .trivial,
            targetStats: [.intelligence],
            trackingType: .manual,
            targetValue: 1,
            unit: "page"
        ),
        DailyQuest(
            title: "Read for 30 Minutes",
            description: "Immerse yourself in wisdom.",
            difficulty: .normal,
            targetStats: [.intelligence],
            trackingType: .screenTime,
            targetValue: 30,
            unit: "minutes",
            screenTimeCategory: "Books"
        ),

        // AGI - Agility
        DailyQuest(
            title: "1 Minute Stretch",
            description: "Flexibility is freedom.",
            difficulty: .trivial,
            targetStats: [.agility],
            trackingType: .manual,
            targetValue: 1,
            unit: "minute"
        ),

        // VIT - Vitality
        DailyQuest(
            title: "Sleep 8 Hours",
            description: "Rest is not weakness. It is regeneration.",
            difficulty: .normal,
            targetStats: [.vitality],
            trackingType: .healthKit,
            targetValue: 8,
            unit: "hours",
            healthKitIdentifier: "HKCategoryTypeIdentifierSleepAnalysis"
        ),
        DailyQuest(
            title: "Drink Water",
            description: "Hydrate your vessel.",
            difficulty: .trivial,
            targetStats: [.vitality],
            trackingType: .manual,
            targetValue: 8,
            unit: "glasses"
        ),

        // WIL - Willpower
        DailyQuest(
            title: "No Social Media Before Noon",
            description: "Guard your morning focus.",
            difficulty: .hard,
            targetStats: [.willpower],
            trackingType: .screenTime,
            targetValue: 0,
            unit: "minutes",
            screenTimeCategory: "SocialMedia"
        ),

        // SPI - Spirit
        DailyQuest(
            title: "1 Minute Meditation",
            description: "Silence the noise. Find your center.",
            difficulty: .trivial,
            targetStats: [.spirit],
            trackingType: .manual,
            targetValue: 1,
            unit: "minute"
        ),
        DailyQuest(
            title: "Write 1 Gratitude",
            description: "Acknowledge the light in darkness.",
            difficulty: .trivial,
            targetStats: [.spirit],
            trackingType: .manual,
            targetValue: 1,
            unit: "gratitude"
        )
    ]

    static let penaltyQuests: [PenaltyQuest] = [
        PenaltyQuest(
            title: "The Plank of Penance",
            description: "Hold a plank for 4 minutes. Feel the burn of failure.",
            penaltyType: .physical
        ),
        PenaltyQuest(
            title: "Public Accountability",
            description: "Post on social media: 'I failed my daily quests. Tomorrow I rise.'",
            penaltyType: .social
        ),
        PenaltyQuest(
            title: "The Fast",
            description: "No snacks or treats today. Only essentials.",
            penaltyType: .restriction
        )
    ]
}
