//
//  GAMELIFEMonitor.swift
//  GAMELIFEMonitor
//
//  [SYSTEM]: Background monitoring extension online.
//  Quest progress tracking active.
//

import DeviceActivity
import ManagedSettings
import FamilyControls
import Foundation

// MARK: - GAMELIFE Device Activity Monitor

/// Extension that monitors app usage in the background
/// Reports quest completions to the main app via shared UserDefaults
class GAMELIFEMonitor: DeviceActivityMonitor {

    // MARK: - Properties

    private let store = ManagedSettingsStore()
    private let appGroupID = "group.com.gamelife.shared"

    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    // MARK: - Interval Events

    /// Called when a monitoring interval starts (e.g., at midnight)
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        log("Interval started for: \(activity.rawValue)")

        // Reset daily progress when the day begins
        resetDailyProgress(for: activity)
    }

    /// Called when a monitoring interval ends
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        log("Interval ended for: \(activity.rawValue)")
    }

    /// Called periodically during active device use (every 15 min by default)
    override func intervalWillStartWarning(for activity: DeviceActivityName) {
        super.intervalWillStartWarning(for: activity)
        // Can be used for progress updates if needed
    }

    override func intervalWillEndWarning(for activity: DeviceActivityName) {
        super.intervalWillEndWarning(for: activity)
    }

    // MARK: - Threshold Events

    /// Called when user reaches the time threshold for tracked apps
    /// This is where we mark quests as completed
    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)

        log("Threshold reached! Event: \(event.rawValue), Activity: \(activity.rawValue)")

        // Extract quest ID from the activity name
        // Activity name format: "quest_<UUID>"
        let activityString = activity.rawValue
        guard activityString.hasPrefix("quest_") else {
            log("Activity is not a quest: \(activityString)")
            return
        }

        let questIdString = String(activityString.dropFirst("quest_".count))
        markQuestAsCompleted(questIdString)
    }

    /// Called when a warning is about to fire (e.g., 5 min before threshold)
    override func eventWillReachThresholdWarning(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventWillReachThresholdWarning(event, activity: activity)
        log("Approaching threshold for: \(event.rawValue)")

        // Could send a notification here if desired
    }

    // MARK: - Quest Completion

    /// Mark a quest as completed in shared storage
    private func markQuestAsCompleted(_ questIdString: String) {
        guard let defaults = sharedDefaults else {
            log("Error: Could not access shared defaults")
            return
        }

        // Get existing completed IDs
        var completedIds = defaults.array(forKey: "completedQuestIds") as? [String] ?? []

        // Add this quest if not already completed
        if !completedIds.contains(questIdString) {
            completedIds.append(questIdString)
            defaults.set(completedIds, forKey: "completedQuestIds")
            defaults.set(Date(), forKey: "lastCompletionDate")

            log("Quest marked complete: \(questIdString)")
        }
    }

    /// Reset daily progress for a quest
    private func resetDailyProgress(for activity: DeviceActivityName) {
        guard activity.rawValue.hasPrefix("quest_") else { return }

        let questIdString = String(activity.rawValue.dropFirst("quest_".count))

        // Clear any stale progress data
        var progressDict = sharedDefaults?.dictionary(forKey: "questProgress") as? [String: Double] ?? [:]
        progressDict[questIdString] = 0.0
        sharedDefaults?.set(progressDict, forKey: "questProgress")
    }

    // MARK: - Logging

    /// Log messages for debugging (writes to shared defaults for retrieval)
    private func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logMessage = "[\(timestamp)] \(message)"

        // Store recent logs for debugging
        var logs = sharedDefaults?.array(forKey: "extensionLogs") as? [String] ?? []
        logs.append(logMessage)

        // Keep only last 50 logs
        if logs.count > 50 {
            logs = Array(logs.suffix(50))
        }

        sharedDefaults?.set(logs, forKey: "extensionLogs")

        #if DEBUG
        print("[GAMELIFEMonitor] \(message)")
        #endif
    }
}
