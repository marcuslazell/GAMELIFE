//
//  QuestManager.swift
//  GAMELIFE
//
//  [SYSTEM]: Quest monitoring subsystem online.
//  Tracking progress across all dimensions.
//

import Foundation
import Combine
import DeviceActivity
import FamilyControls
import UIKit

// MARK: - Quest Manager

/// Manages quest lifecycle and ScreenTime integration
@MainActor
class QuestManager: ObservableObject {

    // MARK: - Singleton

    static let shared = QuestManager()

    // MARK: - Properties

    private let center = DeviceActivityCenter()
    private let appGroupID = "group.com.gamelife.shared"
    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    // Keys for App Group communication
    private enum SharedKeys {
        static let completedQuestIds = "completedQuestIds"
        static let questProgress = "questProgress"
        static let lastSyncDate = "lastSyncDate"
        static let monitoringQuests = "monitoringQuests"
        static let activeScreenTimeQuests = "activeScreenTimeQuests"
        static let extensionLogs = "extensionLogs"
    }

    // MARK: - Initialization

    private init() {
        // Register for app becoming active to check extension completions
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    // MARK: - ScreenTime Monitoring

    /// Start monitoring app usage for a quest
    /// - Parameters:
    ///   - quest: The quest to monitor
    ///   - apps: The selected apps/categories to track
    func startMonitoring(for quest: DailyQuest, apps: FamilyActivitySelection) {
        guard AppFeatureFlags.screenTimeEnabled else { return }
        guard quest.trackingType == .screenTime else { return }

        let activityName = DeviceActivityName("quest_\(quest.id.uuidString)")

        // Schedule for the entire day (resets at midnight)
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )

        // Create threshold event based on quest target
        let thresholdMinutes = Int(quest.targetValue)
        let event = DeviceActivityEvent(
            applications: apps.applicationTokens,
            categories: apps.categoryTokens,
            threshold: DateComponents(minute: thresholdMinutes)
        )

        do {
            try center.startMonitoring(
                activityName,
                during: schedule,
                events: [DeviceActivityEvent.Name("threshold_\(quest.id.uuidString)"): event]
            )

            // Store the monitoring state
            saveMonitoringState(questId: quest.id, apps: apps)

            print("[SYSTEM] Started monitoring for quest: \(quest.title)")
        } catch {
            print("[SYSTEM] Failed to start monitoring: \(error.localizedDescription)")
        }
    }

    /// Stop monitoring for a quest
    func stopMonitoring(for quest: DailyQuest) {
        let activityName = DeviceActivityName("quest_\(quest.id.uuidString)")
        center.stopMonitoring([activityName])

        // Clear monitoring state
        clearMonitoringState(questId: quest.id)

        print("[SYSTEM] Stopped monitoring for quest: \(quest.title)")
    }

    /// Stop all monitoring
    func stopAllMonitoring() {
        center.stopMonitoring()
        sharedDefaults?.removeObject(forKey: SharedKeys.monitoringQuests)
        print("[SYSTEM] All monitoring stopped")
    }

    // MARK: - Extension Communication

    /// Check for quest completions reported by the DeviceActivityMonitor extension
    func checkExtensionCompletions() {
        guard AppFeatureFlags.screenTimeEnabled else { return }
        guard let completedIds = sharedDefaults?.array(forKey: SharedKeys.completedQuestIds) as? [String] else {
            return
        }

        guard !completedIds.isEmpty else { return }

        print("[SYSTEM] Found \(completedIds.count) completed quest(s) from extension")

        for questIdString in completedIds {
            if let uuid = UUID(uuidString: questIdString) {
                completeQuestFromExtension(questId: uuid)
            }
        }

        // Clear processed completions
        sharedDefaults?.removeObject(forKey: SharedKeys.completedQuestIds)
        sharedDefaults?.set(Date(), forKey: SharedKeys.lastSyncDate)
    }

    /// Get progress updates from extension
    func getProgressFromExtension() -> [UUID: Double] {
        guard AppFeatureFlags.screenTimeEnabled else { return [:] }
        guard let progressData = sharedDefaults?.dictionary(forKey: SharedKeys.questProgress) as? [String: Double] else {
            return [:]
        }

        var progress: [UUID: Double] = [:]
        for (idString, value) in progressData {
            if let uuid = UUID(uuidString: idString) {
                progress[uuid] = value
            }
        }

        return progress
    }

    // MARK: - Private Helpers

    private func completeQuestFromExtension(questId: UUID) {
        // Find the quest and complete it
        if let quest = GameEngine.shared.dailyQuests.first(where: { $0.id == questId }) {
            let result = GameEngine.shared.completeQuest(quest, sendSystemNotification: false)
            guard result.success else { return }

            // Show system message
            SystemMessageHelper.showQuestComplete(
                title: quest.title,
                xp: result.xpAwarded,
                gold: result.goldAwarded
            )
        }
    }

    private func saveMonitoringState(questId: UUID, apps: FamilyActivitySelection) {
        var monitoringQuests = sharedDefaults?.dictionary(forKey: SharedKeys.monitoringQuests) as? [String: Data] ?? [:]

        // Encode the FamilyActivitySelection
        if let encoded = try? JSONEncoder().encode(apps) {
            monitoringQuests[questId.uuidString] = encoded
            sharedDefaults?.set(monitoringQuests, forKey: SharedKeys.monitoringQuests)
        }
    }

    private func clearMonitoringState(questId: UUID) {
        var monitoringQuests = sharedDefaults?.dictionary(forKey: SharedKeys.monitoringQuests) as? [String: Data] ?? [:]
        monitoringQuests.removeValue(forKey: questId.uuidString)
        sharedDefaults?.set(monitoringQuests, forKey: SharedKeys.monitoringQuests)
    }

    @objc private func appDidBecomeActive() {
        guard AppFeatureFlags.screenTimeEnabled else { return }
        checkExtensionCompletions()
    }

    // MARK: - Quest Sync

    /// Sync all active ScreenTime quests with the extension
    func syncActiveQuests(_ quests: [DailyQuest]) {
        guard AppFeatureFlags.screenTimeEnabled else {
            sharedDefaults?.removeObject(forKey: SharedKeys.activeScreenTimeQuests)
            return
        }
        let screenTimeQuests = quests.filter {
            $0.trackingType == .screenTime && $0.status != .completed
        }

        // Write quest data to shared storage for extension access
        var questData: [[String: Any]] = []
        for quest in screenTimeQuests {
            questData.append([
                "id": quest.id.uuidString,
                "title": quest.title,
                "targetValue": quest.targetValue,
                "xpReward": quest.xpReward,
                "goldReward": quest.goldReward
            ])
        }

        sharedDefaults?.set(questData, forKey: SharedKeys.activeScreenTimeQuests)
        sharedDefaults?.set(Date(), forKey: SharedKeys.lastSyncDate)
    }

    /// Ensure all active Screen Time quests are monitored and stale monitors are removed.
    func synchronizeMonitoring(with quests: [DailyQuest]) {
        guard AppFeatureFlags.screenTimeEnabled else {
            stopAllMonitoring()
            sharedDefaults?.removeObject(forKey: SharedKeys.activeScreenTimeQuests)
            return
        }
        let activeScreenTimeQuests = quests.filter {
            $0.trackingType == .screenTime && $0.status != .completed
        }

        var activeIDs = Set<UUID>()
        for quest in activeScreenTimeQuests {
            activeIDs.insert(quest.id)
            guard let data = quest.screenTimeSelectionData,
                  let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data),
                  (!selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty) else {
                continue
            }
            startMonitoring(for: quest, apps: selection)
        }

        let monitoredQuestIDs = currentlyMonitoredQuestIDs()
        for questID in monitoredQuestIDs where !activeIDs.contains(questID) {
            let placeholderQuest = DailyQuest(
                id: questID,
                title: "Screen Time Quest",
                description: "",
                targetStats: [.willpower],
                trackingType: .screenTime
            )
            stopMonitoring(for: placeholderQuest)
        }

        syncActiveQuests(quests)
    }

    func latestExtensionLog() -> String? {
        (sharedDefaults?.array(forKey: SharedKeys.extensionLogs) as? [String])?.last
    }

    private func currentlyMonitoredQuestIDs() -> Set<UUID> {
        let map = sharedDefaults?.dictionary(forKey: SharedKeys.monitoringQuests) as? [String: Data] ?? [:]
        let ids = map.keys.compactMap(UUID.init(uuidString:))
        return Set(ids)
    }
}

// MARK: - DeviceActivityName Extension

extension DeviceActivityName {
    init(_ name: String) {
        self.init(rawValue: name)
    }
}

// MARK: - DeviceActivityEvent.Name Extension

extension DeviceActivityEvent.Name {
    init(_ name: String) {
        self.init(rawValue: name)
    }
}
