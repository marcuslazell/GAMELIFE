//
//  ScreenTimeManager.swift
//  GAMELIFE
//
//  [SYSTEM]: Mind activity scanner initialized.
//  Your digital habits are now monitored.
//

import Foundation
import FamilyControls
import DeviceActivity
import ManagedSettings
import Combine

// MARK: - Screen Time Manager

/// Manages Screen Time API interactions for automatic quest tracking
/// Tracks: App usage by category, focus time, social media avoidance
@MainActor
class ScreenTimeManager: ObservableObject {

    static let shared = ScreenTimeManager()

    // MARK: - Published Properties

    @Published var isAuthorized = false
    @Published var selectedAppsToBlock: FamilyActivitySelection = FamilyActivitySelection()
    @Published var selectedAppsToTrack: FamilyActivitySelection = FamilyActivitySelection()
    @Published var lastSyncDate: Date?
    @Published var lastDetectedEvent: String = "No Screen Time events detected yet."
    @Published var isUsageMonitoringActive = false

    // Usage tracking
    @Published var socialMediaMinutesToday: Int = 0
    @Published var readingMinutesToday: Int = 0
    @Published var productivityMinutesToday: Int = 0
    @Published var entertainmentMinutesToday: Int = 0

    // Blocking status
    @Published var isBlockingEnabled = false
    @Published var currentBlockingSession: BlockingSession?
    @Published private(set) var trackedUsageMinutesBySelection: [String: Int] = [:]

    // MARK: - Private Properties

    private let center = AuthorizationCenter.shared
    private let store = ManagedSettingsStore()
    private let deviceActivityCenter = DeviceActivityCenter()
    private let usageStoreKey = "screenTimeTrackedUsageBySelection"
    private let usageStoreDayKey = "screenTimeTrackedUsageDay"

    // MARK: - Initialization

    private init() {
        loadTrackedUsage()
        refreshAuthorizationStatus()
        resetTrackedUsageIfNeeded()
    }

    // MARK: - Authorization

    /// Request Screen Time authorization
    func requestAuthorization() async throws {
        if center.authorizationStatus == .approved {
            isAuthorized = true
            return
        }

        try await center.requestAuthorization(for: .individual)
        refreshAuthorizationStatus()

        if !isAuthorized {
            throw ScreenTimeAuthorizationError.notAuthorized
        }
    }

    /// Check current authorization status
    func refreshAuthorizationStatus() {
        switch center.authorizationStatus {
        case .approved:
            isAuthorized = true
        case .denied, .notDetermined:
            isAuthorized = false
        @unknown default:
            isAuthorized = false
        }
    }

    // MARK: - App Category Definitions

    /// App categories for tracking and blocking
    enum AppCategory: String, CaseIterable {
        case socialMedia = "Social Media"
        case reading = "Reading & Education"
        case productivity = "Productivity"
        case entertainment = "Entertainment"
        case games = "Games"
        case health = "Health & Fitness"

        var bundleIdentifierPrefixes: [String] {
            switch self {
            case .socialMedia:
                return [
                    "com.facebook",
                    "com.instagram",
                    "com.twitter",
                    "com.tiktok",
                    "com.snapchat",
                    "com.linkedin",
                    "com.reddit",
                    "net.whatsapp"
                ]
            case .reading:
                return [
                    "com.apple.iBooks",
                    "com.amazon.Kindle",
                    "com.audible",
                    "com.medium",
                    "com.pocket"
                ]
            case .productivity:
                return [
                    "com.apple.Notes",
                    "com.notion",
                    "com.todoist",
                    "com.asana",
                    "com.trello",
                    "com.slack",
                    "com.microsoft"
                ]
            case .entertainment:
                return [
                    "com.netflix",
                    "com.disney",
                    "com.hbo",
                    "com.hulu",
                    "com.youtube",
                    "com.spotify",
                    "com.apple.TV"
                ]
            case .games:
                return [] // Use ActivityCategoryToken for games
            case .health:
                return [
                    "com.apple.Health",
                    "com.headspace",
                    "com.calm",
                    "com.strava",
                    "com.nike"
                ]
            }
        }

        var statContribution: StatType {
            switch self {
            case .socialMedia: return .willpower // Avoiding it builds willpower
            case .reading: return .intelligence
            case .productivity: return .intelligence
            case .entertainment: return .spirit // In moderation
            case .games: return .agility // Reaction time, strategy
            case .health: return .vitality
            }
        }
    }

    // MARK: - App Blocking (Dungeon Mode)

    /// Start blocking distracting apps for a dungeon session
    func startDungeonBlocking(duration: TimeInterval, categories: [AppCategory] = [.socialMedia, .entertainment, .games]) {
        guard isAuthorized else { return }

        // Create blocking session
        currentBlockingSession = BlockingSession(
            startTime: Date(),
            duration: duration,
            blockedCategories: categories
        )

        // Apply restrictions
        store.shield.applications = selectedAppsToBlock.applicationTokens
        store.shield.applicationCategories = .specific(selectedAppsToBlock.categoryTokens)

        isBlockingEnabled = true

        // Schedule end of blocking
        scheduleBlockingEnd(after: duration)
    }

    /// End app blocking
    func endDungeonBlocking() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        isBlockingEnabled = false
        currentBlockingSession = nil
    }

    /// Schedule automatic end of blocking
    private func scheduleBlockingEnd(after duration: TimeInterval) {
        // Use DeviceActivitySchedule for automatic unblocking
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: false
        )

        do {
            try deviceActivityCenter.startMonitoring(
                .init("dungeon_session"),
                during: schedule
            )
        } catch {
            print("[SYSTEM] Failed to start activity monitoring: \(error)")
        }
    }

    // MARK: - Usage Tracking

    /// Start monitoring app usage for quest tracking
    func startUsageMonitoring() {
        guard isAuthorized else { return }
        resetTrackedUsageIfNeeded()

        // Set up daily monitoring schedule
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )

        do {
            try deviceActivityCenter.startMonitoring(
                .init("daily_tracking"),
                during: schedule
            )
            isUsageMonitoringActive = true
            recordSync(event: "Screen Time monitoring active")
        } catch {
            isUsageMonitoringActive = false
            print("[SYSTEM] Failed to start usage monitoring: \(error)")
        }
    }

    /// Stop monitoring
    func stopUsageMonitoring() {
        deviceActivityCenter.stopMonitoring([.init("daily_tracking")])
        isUsageMonitoringActive = false
    }

    /// Evaluate auto-tracking progress for a Screen Time quest.
    func checkQuestProgress(for quest: DailyQuest) -> Double {
        guard quest.trackingType == .screenTime else { return 0 }
        guard isAuthorized else { return 0 }

        resetTrackedUsageIfNeeded()
        let target = max(1.0, quest.targetValue)

        if let data = quest.screenTimeSelectionData,
           let selection = decodeSelection(from: data),
           !isSelectionEmpty(selection) {
            let minutes = usageMinutes(for: selection)
            recordSync(event: "Usage sampled: \(minutes) min")
            return min(1.0, Double(minutes) / target)
        }

        // Fallback for legacy quests that only persisted a category label.
        let minutes = usageMinutes(forCategoryLabel: quest.screenTimeCategory)
        recordSync(event: "Category sampled: \(minutes) min")
        return min(1.0, Double(minutes) / target)
    }

    /// Record usage minutes for a concrete Family Controls selection.
    /// This can be called by a Screen Time report/monitor pipeline.
    func recordTrackedUsage(minutes: Int, for selection: FamilyActivitySelection) {
        resetTrackedUsageIfNeeded()
        guard let key = selectionUsageKey(for: selection) else { return }
        trackedUsageMinutesBySelection[key] = max(0, minutes)
        persistTrackedUsage()
        recordSync(event: "Usage update: \(max(0, minutes)) min")
        NotificationCenter.default.post(name: .screenTimeDataDidUpdate, object: nil)
    }

    /// Record aggregate category usage snapshots.
    func recordCategoryUsage(
        readingMinutes: Int? = nil,
        productivityMinutes: Int? = nil,
        socialMediaMinutes: Int? = nil,
        entertainmentMinutes: Int? = nil
    ) {
        resetTrackedUsageIfNeeded()
        if let readingMinutes {
            self.readingMinutesToday = max(0, readingMinutes)
        }
        if let productivityMinutes {
            self.productivityMinutesToday = max(0, productivityMinutes)
        }
        if let socialMediaMinutes {
            self.socialMediaMinutesToday = max(0, socialMediaMinutes)
        }
        if let entertainmentMinutes {
            self.entertainmentMinutesToday = max(0, entertainmentMinutes)
        }
        recordSync(event: "Category usage snapshot updated")

        NotificationCenter.default.post(name: .screenTimeDataDidUpdate, object: nil)
    }

    // MARK: - Quest Integration

    /// Check if user avoided social media before a certain time
    func checkSocialMediaAvoidance(beforeHour: Int) -> Bool {
        // This would need DeviceActivityReport data
        // For now, return based on tracked minutes
        return socialMediaMinutesToday == 0
    }

    /// Check reading app usage
    func checkReadingProgress(targetMinutes: Int) -> Double {
        return Double(readingMinutesToday) / Double(targetMinutes)
    }

    /// Calculate INT XP based on productive app usage
    func calculateIntelligenceXP() -> Int {
        // XP formula: 1 XP per 5 minutes of reading/productivity apps
        let productiveMinutes = readingMinutesToday + productivityMinutesToday
        return productiveMinutes / 5
    }

    /// Calculate WIL XP based on social media avoidance
    func calculateWillpowerXP() -> Int {
        // XP formula: Bonus XP for keeping social media under 30 mins
        if socialMediaMinutesToday == 0 {
            return 20 // Perfect avoidance bonus
        } else if socialMediaMinutesToday <= 15 {
            return 15
        } else if socialMediaMinutesToday <= 30 {
            return 10
        } else if socialMediaMinutesToday <= 60 {
            return 5
        }
        return 0
    }

    // MARK: - App Selection UI Support

    /// Present the Family Controls app picker
    func presentAppPicker() {
        // This is handled via FamilyActivityPicker in SwiftUI
        // The selection binding updates selectedAppsToBlock/selectedAppsToTrack
    }

    /// Get human-readable summary of selected apps
    func getSelectionSummary(_ selection: FamilyActivitySelection) -> String {
        let appCount = selection.applicationTokens.count
        let categoryCount = selection.categoryTokens.count

        if appCount == 0 && categoryCount == 0 {
            return "No apps selected"
        }

        var parts: [String] = []
        if appCount > 0 {
            parts.append("\(appCount) app\(appCount == 1 ? "" : "s")")
        }
        if categoryCount > 0 {
            parts.append("\(categoryCount) categor\(categoryCount == 1 ? "y" : "ies")")
        }

        return parts.joined(separator: ", ")
    }

    func encodeSelection(_ selection: FamilyActivitySelection) -> Data? {
        try? JSONEncoder().encode(selection)
    }

    func decodeSelection(from data: Data) -> FamilyActivitySelection? {
        try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
    }

    private func usageMinutes(for selection: FamilyActivitySelection) -> Int {
        guard let key = selectionUsageKey(for: selection) else { return 0 }
        return trackedUsageMinutesBySelection[key] ?? 0
    }

    private func usageMinutes(forCategoryLabel label: String?) -> Int {
        guard let label else {
            return readingMinutesToday + productivityMinutesToday
        }

        switch label.lowercased() {
        case "socialmedia", "social media":
            return socialMediaMinutesToday
        case "reading", "books":
            return readingMinutesToday
        case "productivity", "deepwork", "deep work":
            return productivityMinutesToday
        case "entertainment":
            return entertainmentMinutesToday
        default:
            return readingMinutesToday + productivityMinutesToday
        }
    }

    private func isSelectionEmpty(_ selection: FamilyActivitySelection) -> Bool {
        selection.applicationTokens.isEmpty && selection.categoryTokens.isEmpty
    }

    private func selectionUsageKey(for selection: FamilyActivitySelection) -> String? {
        encodeSelection(selection)?.base64EncodedString()
    }

    private func resetTrackedUsageIfNeeded() {
        let currentDay = currentDayKey()
        let storedDay = UserDefaults.standard.string(forKey: usageStoreDayKey)
        guard storedDay != currentDay else { return }

        trackedUsageMinutesBySelection = [:]
        socialMediaMinutesToday = 0
        readingMinutesToday = 0
        productivityMinutesToday = 0
        entertainmentMinutesToday = 0
        persistTrackedUsage()
    }

    private func persistTrackedUsage() {
        UserDefaults.standard.set(trackedUsageMinutesBySelection, forKey: usageStoreKey)
        UserDefaults.standard.set(currentDayKey(), forKey: usageStoreDayKey)
    }

    private func loadTrackedUsage() {
        trackedUsageMinutesBySelection = UserDefaults.standard.dictionary(forKey: usageStoreKey) as? [String: Int] ?? [:]
    }

    private func currentDayKey() -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    private func recordSync(event: String) {
        lastSyncDate = Date()
        lastDetectedEvent = event
    }
}

enum ScreenTimeAuthorizationError: LocalizedError {
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Screen Time authorization is still unavailable for this device/account."
        }
    }
}

// MARK: - Blocking Session

struct BlockingSession: Codable {
    let id: UUID
    let startTime: Date
    let duration: TimeInterval
    let blockedCategories: [ScreenTimeManager.AppCategory]

    var endTime: Date {
        startTime.addingTimeInterval(duration)
    }

    var isActive: Bool {
        Date() < endTime
    }

    var remainingTime: TimeInterval {
        max(0, endTime.timeIntervalSince(Date()))
    }

    init(startTime: Date, duration: TimeInterval, blockedCategories: [ScreenTimeManager.AppCategory]) {
        self.id = UUID()
        self.startTime = startTime
        self.duration = duration
        self.blockedCategories = blockedCategories
    }

    enum CodingKeys: String, CodingKey {
        case id, startTime, duration, blockedCategories
    }
}

extension ScreenTimeManager.AppCategory: Codable {}

extension Notification.Name {
    static let screenTimeDataDidUpdate = Notification.Name("screenTimeDataDidUpdate")
}

// MARK: - Device Activity Monitor Extension

/// This extension would be in a separate App Extension target
/// It monitors device activity and reports back to the main app
/*
class GameLifeDeviceActivityMonitor: DeviceActivityMonitor {

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)

        // Dungeon started - blocking is active
        if activity.rawValue == "dungeon_session" {
            // Post notification that dungeon mode is active
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)

        // Dungeon ended - remove blocking
        if activity.rawValue == "dungeon_session" {
            let store = ManagedSettingsStore()
            store.shield.applications = nil
            store.shield.applicationCategories = nil
        }
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)

        // User hit a usage threshold
        // Send notification or update quest progress
    }
}
*/

// MARK: - Device Activity Report Extension

/// This extension would generate usage reports
/*
struct GameLifeDeviceActivityReport: DeviceActivityReportScene {

    let context: DeviceActivityReport.Context

    var body: some DeviceActivityReportScene {
        TotalActivityReport { totalActivity in
            // Process total activity data
            // Update quest progress based on app usage
        }
    }
}
*/

// MARK: - Screen Time Quest Definitions

extension ScreenTimeManager {

    /// Create default Screen Time-tracked quests
    static func createDefaultScreenTimeQuests() -> [DailyQuest] {
        [
            DailyQuest(
                title: "Read for 30 Minutes",
                description: "Spend time in reading apps.",
                difficulty: .normal,
                targetStats: [.intelligence],
                trackingType: .screenTime,
                targetValue: 30,
                unit: "minutes",
                screenTimeCategory: "Reading"
            ),
            DailyQuest(
                title: "No Social Media Before Noon",
                description: "Guard your morning focus.",
                difficulty: .hard,
                targetStats: [.willpower],
                trackingType: .screenTime,
                targetValue: 0,
                unit: "minutes before noon",
                screenTimeCategory: "SocialMedia"
            ),
            DailyQuest(
                title: "Social Media Under 30 Mins",
                description: "Limit the scroll.",
                difficulty: .normal,
                targetStats: [.willpower],
                trackingType: .screenTime,
                targetValue: 30,
                unit: "minutes max",
                screenTimeCategory: "SocialMedia"
            ),
            DailyQuest(
                title: "Deep Work Session",
                description: "Complete a dungeon without touching distractions.",
                difficulty: .hard,
                targetStats: [.willpower, .intelligence],
                trackingType: .screenTime,
                targetValue: 25,
                unit: "focused minutes",
                screenTimeCategory: "DeepWork"
            )
        ]
    }
}
