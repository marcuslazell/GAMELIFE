//
//  DataManagers.swift
//  GAMELIFE
//
//  [SYSTEM]: Data persistence modules initialized.
//  Your progress is being recorded.
//

import Foundation

// MARK: - Player Data Manager

/// Manages player data persistence
class PlayerDataManager {

    static let shared = PlayerDataManager()

    private let playerKey = "gamelife_player"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {}

    // MARK: - Player Persistence

    /// Save player to UserDefaults
    func savePlayer(_ player: Player) {
        do {
            let data = try encoder.encode(player)
            UserDefaults.standard.set(data, forKey: playerKey)
        } catch {
            print("[SYSTEM] Failed to save player: \(error)")
        }
    }

    /// Load player from UserDefaults
    func loadPlayer() -> Player? {
        guard let data = UserDefaults.standard.data(forKey: playerKey) else {
            return nil
        }

        do {
            return try decoder.decode(Player.self, from: data)
        } catch {
            print("[SYSTEM] Failed to load player: \(error)")
            return nil
        }
    }

    /// Delete player data
    func deletePlayer() {
        UserDefaults.standard.removeObject(forKey: playerKey)
    }

    /// Check if player exists
    var playerExists: Bool {
        UserDefaults.standard.data(forKey: playerKey) != nil
    }

    /// Export player data as JSON string
    func exportPlayerData() -> String? {
        guard let player = loadPlayer() else { return nil }

        do {
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(player)
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    /// Import player data from JSON string
    func importPlayerData(_ jsonString: String) -> Bool {
        guard let data = jsonString.data(using: .utf8) else { return false }

        do {
            let player = try decoder.decode(Player.self, from: data)
            savePlayer(player)
            return true
        } catch {
            print("[SYSTEM] Failed to import player: \(error)")
            return false
        }
    }
}

// MARK: - Quest Data Manager

/// Manages quest data persistence
class QuestDataManager {

    static let shared = QuestDataManager()

    private let dailyQuestsKey = "gamelife_daily_quests"
    private let bossFightsKey = "gamelife_boss_fights"
    private let completedQuestsKey = "gamelife_completed_quests"
    private let questHistoryKey = "gamelife_quest_history"

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {}

    // MARK: - Daily Quests

    /// Save daily quests
    func saveDailyQuests(_ quests: [DailyQuest]) {
        do {
            let data = try encoder.encode(quests)
            UserDefaults.standard.set(data, forKey: dailyQuestsKey)
        } catch {
            print("[SYSTEM] Failed to save daily quests: \(error)")
        }
    }

    /// Load daily quests
    func loadDailyQuests() -> [DailyQuest]? {
        guard let data = UserDefaults.standard.data(forKey: dailyQuestsKey) else {
            return nil
        }

        do {
            return try decoder.decode([DailyQuest].self, from: data)
        } catch {
            print("[SYSTEM] Failed to load daily quests: \(error)")
            return nil
        }
    }

    /// Reset daily quests (called at midnight)
    func resetDailyQuests() -> [DailyQuest] {
        let emptyQuests: [DailyQuest] = []
        saveDailyQuests(emptyQuests)
        return emptyQuests
    }

    // MARK: - Boss Fights

    /// Save boss fights
    func saveBossFights(_ bossFights: [BossFight]) {
        do {
            let data = try encoder.encode(bossFights)
            UserDefaults.standard.set(data, forKey: bossFightsKey)
        } catch {
            print("[SYSTEM] Failed to save boss fights: \(error)")
        }
    }

    /// Load boss fights
    func loadBossFights() -> [BossFight]? {
        guard let data = UserDefaults.standard.data(forKey: bossFightsKey) else {
            return nil
        }

        do {
            return try decoder.decode([BossFight].self, from: data)
        } catch {
            print("[SYSTEM] Failed to load boss fights: \(error)")
            return nil
        }
    }

    // MARK: - Quest History

    /// Record a completed quest in history
    func recordCompletedQuest(_ quest: any QuestProtocol, xpAwarded: Int, goldAwarded: Int) {
        var history = loadQuestHistory()

        let record = QuestHistoryRecord(
            questId: quest.id,
            questTitle: quest.title,
            questType: quest.questType,
            difficulty: quest.difficulty,
            completedAt: Date(),
            xpAwarded: xpAwarded,
            goldAwarded: goldAwarded
        )

        history.append(record)

        // Keep only last 1000 records
        if history.count > 1000 {
            history = Array(history.suffix(1000))
        }

        saveQuestHistory(history)
    }

    /// Save quest history
    private func saveQuestHistory(_ history: [QuestHistoryRecord]) {
        do {
            let data = try encoder.encode(history)
            UserDefaults.standard.set(data, forKey: questHistoryKey)
        } catch {
            print("[SYSTEM] Failed to save quest history: \(error)")
        }
    }

    /// Load quest history
    func loadQuestHistory() -> [QuestHistoryRecord] {
        guard let data = UserDefaults.standard.data(forKey: questHistoryKey) else {
            return []
        }

        do {
            return try decoder.decode([QuestHistoryRecord].self, from: data)
        } catch {
            print("[SYSTEM] Failed to load quest history: \(error)")
            return []
        }
    }

    /// Replace quest history with imported/synced records.
    func overwriteQuestHistory(_ history: [QuestHistoryRecord]) {
        saveQuestHistory(history)
    }

    /// Get statistics from quest history
    func getQuestStatistics() -> QuestStatistics {
        let history = loadQuestHistory()
        let now = Date()
        let calendar = Calendar.current

        // Today's stats
        let todayStart = calendar.startOfDay(for: now)
        let todayQuests = history.filter { $0.completedAt >= todayStart }

        // This week's stats
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? todayStart
        let weekQuests = history.filter { $0.completedAt >= weekStart }

        // This month's stats
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? todayStart
        let monthQuests = history.filter { $0.completedAt >= monthStart }

        return QuestStatistics(
            totalCompleted: history.count,
            todayCompleted: todayQuests.count,
            weekCompleted: weekQuests.count,
            monthCompleted: monthQuests.count,
            totalXPEarned: history.reduce(0) { $0 + $1.xpAwarded },
            totalGoldEarned: history.reduce(0) { $0 + $1.goldAwarded },
            dailyQuestsCompleted: history.filter { $0.questType == .daily }.count,
            bossesDefeated: history.filter { $0.questType == .boss }.count,
            dungeonsCleared: history.filter { $0.questType == .dungeon }.count
        )
    }
}

// MARK: - Quest History Record

struct QuestHistoryRecord: Codable {
    let questId: UUID
    let questTitle: String
    let questType: QuestType
    let difficulty: QuestDifficulty
    let completedAt: Date
    let xpAwarded: Int
    let goldAwarded: Int
}

// MARK: - Quest Statistics

struct QuestStatistics {
    let totalCompleted: Int
    let todayCompleted: Int
    let weekCompleted: Int
    let monthCompleted: Int
    let totalXPEarned: Int
    let totalGoldEarned: Int
    let dailyQuestsCompleted: Int
    let bossesDefeated: Int
    let dungeonsCleared: Int
}

// MARK: - Activity Log Data Manager

/// Persists recent activity entries for the Status screen.
class ActivityLogDataManager {

    static let shared = ActivityLogDataManager()

    private let activityLogKey = "gamelife_recent_activity"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {}

    func loadActivityLog() -> [ActivityLogEntry] {
        guard let data = UserDefaults.standard.data(forKey: activityLogKey) else {
            return []
        }

        do {
            return try decoder.decode([ActivityLogEntry].self, from: data)
        } catch {
            print("[SYSTEM] Failed to load recent activity: \(error)")
            return []
        }
    }

    func saveActivityLog(_ entries: [ActivityLogEntry]) {
        do {
            let data = try encoder.encode(entries)
            UserDefaults.standard.set(data, forKey: activityLogKey)
        } catch {
            print("[SYSTEM] Failed to save recent activity: \(error)")
        }
    }

    func appendActivity(_ entry: ActivityLogEntry, maxEntries: Int = 100) {
        var entries = loadActivityLog()
        entries.insert(entry, at: 0)

        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }

        saveActivityLog(entries)
    }
}

// MARK: - Settings Manager

/// Manages app settings
class SettingsManager {

    static let shared = SettingsManager()

    private init() {}

    // MARK: - User Defaults Keys

    private enum Keys {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let soundEnabled = "soundEnabled"
        static let hapticEnabled = "hapticEnabled"
        static let dailyReminderTime = "dailyReminderTime"
        static let eveningReminderEnabled = "eveningReminderEnabled"
        static let streakAlertsEnabled = "streakAlertsEnabled"
        static let autoTrackHealthKit = "autoTrackHealthKit"
        static let autoTrackScreenTime = "autoTrackScreenTime"
        static let autoTrackLocation = "autoTrackLocation"
    }

    // MARK: - Onboarding

    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.hasCompletedOnboarding) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.hasCompletedOnboarding) }
    }

    // MARK: - Sound & Haptics

    var soundEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.soundEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.soundEnabled) }
    }

    var hapticEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.hapticEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.hapticEnabled) }
    }

    // MARK: - Notifications

    var dailyReminderTime: Date {
        get {
            UserDefaults.standard.object(forKey: Keys.dailyReminderTime) as? Date ?? defaultReminderTime
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.dailyReminderTime)
        }
    }

    var eveningReminderEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.eveningReminderEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.eveningReminderEnabled) }
    }

    var streakAlertsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.streakAlertsEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.streakAlertsEnabled) }
    }

    private var defaultReminderTime: Date {
        var components = DateComponents()
        components.hour = 8
        components.minute = 0
        return Calendar.current.date(from: components) ?? Date()
    }

    // MARK: - Auto-Tracking

    var autoTrackHealthKit: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.autoTrackHealthKit) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.autoTrackHealthKit) }
    }

    var autoTrackScreenTime: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.autoTrackScreenTime) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.autoTrackScreenTime) }
    }

    var autoTrackLocation: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.autoTrackLocation) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.autoTrackLocation) }
    }

    // MARK: - Reset

    func resetAllSettings() {
        guard let domain = Bundle.main.bundleIdentifier else { return }
        UserDefaults.standard.removePersistentDomain(forName: domain)
    }

    func setDefaults() {
        let defaults: [String: Any] = [
            Keys.soundEnabled: true,
            Keys.hapticEnabled: true,
            Keys.eveningReminderEnabled: true,
            Keys.streakAlertsEnabled: true,
            Keys.autoTrackHealthKit: false,  // Disabled by default - requires Info.plist setup
            Keys.autoTrackScreenTime: false, // Disabled by default - requires entitlement
            Keys.autoTrackLocation: false    // Disabled by default - requires Info.plist setup
        ]

        UserDefaults.standard.register(defaults: defaults)
    }
}

// MARK: - Location Data Manager

/// Manages saved locations for geofencing
class LocationDataManager {

    static let shared = LocationDataManager()

    private let locationsKey = "gamelife_tracked_locations"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {}

    /// Save tracked locations
    func saveLocations(_ locations: [TrackedLocation]) {
        do {
            let data = try encoder.encode(locations)
            UserDefaults.standard.set(data, forKey: locationsKey)
        } catch {
            print("[SYSTEM] Failed to save locations: \(error)")
        }
    }

    /// Load tracked locations
    func loadLocations() -> [TrackedLocation] {
        guard let data = UserDefaults.standard.data(forKey: locationsKey) else {
            return []
        }

        do {
            return try decoder.decode([TrackedLocation].self, from: data)
        } catch {
            print("[SYSTEM] Failed to load locations: \(error)")
            return []
        }
    }

    /// Add a new location
    func addLocation(_ location: TrackedLocation) {
        var locations = loadLocations()
        locations.append(location)
        saveLocations(locations)
    }

    /// Remove a location
    func removeLocation(_ location: TrackedLocation) {
        var locations = loadLocations()
        locations.removeAll { $0.id == location.id }
        saveLocations(locations)
    }
}
