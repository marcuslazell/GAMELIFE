//
//  WatchConnectivityManager.swift
//  GAMELIFE
//
//  [SYSTEM]: Watch relay initialized.
//  Quest data can now synchronize with Apple Watch companions.
//

import Foundation
import Combine
import WatchConnectivity

@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {

    static let shared = WatchConnectivityManager()

    @Published private(set) var isSupported = WCSession.isSupported()
    @Published private(set) var isPaired = false
    @Published private(set) var isWatchAppInstalled = false
    @Published private(set) var isReachable = false
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var lastSyncEvent = "Watch sync idle."

    private let snapshotContextKey = "snapshotData"
    private let schemaVersionKey = "schemaVersion"
    private let messageTypeKey = "type"
    private let commandKey = "command"
    private let questIDKey = "questID"
    private let queuedQuestIDsKey = "queuedCompleteQuestIDs"
    private let syncSchemaVersion = 1

    private var latestSnapshotData: Data?

    private override init() {
        super.init()
        activateSessionIfSupported()
    }

    func activateSessionIfSupported() {
        guard WCSession.isSupported() else {
            isSupported = false
            return
        }

        let session = WCSession.default
        session.delegate = self
        session.activate()
        applySessionState(from: session)
    }

    func publishSnapshot(player: Player, quests: [DailyQuest], activities: [ActivityLogEntry]) {
        guard WCSession.isSupported() else { return }
        guard let data = makeSnapshotData(player: player, quests: quests, activities: activities) else { return }

        latestSnapshotData = data
        sendSnapshotContext(data)
    }

    private func applySessionState(from session: WCSession) {
        isSupported = WCSession.isSupported()
        isPaired = session.isPaired
        isWatchAppInstalled = session.isWatchAppInstalled
        isReachable = session.isReachable
    }

    private func sendSnapshotContext(_ data: Data) {
        let session = WCSession.default
        guard session.activationState == .activated else {
            lastSyncEvent = "Watch session not yet activated."
            return
        }

        do {
            try session.updateApplicationContext([
                snapshotContextKey: data,
                schemaVersionKey: syncSchemaVersion
            ])
            lastSyncDate = Date()
            lastSyncEvent = "Snapshot pushed to watch context."
        } catch {
            lastSyncEvent = "Watch context update failed: \(error.localizedDescription)"
        }

        if session.isReachable {
            session.sendMessage(
                [
                    messageTypeKey: "snapshot",
                    snapshotContextKey: data,
                    schemaVersionKey: syncSchemaVersion
                ],
                replyHandler: nil,
                errorHandler: { [weak self] error in
                    Task { @MainActor in
                        self?.lastSyncEvent = "Reachable snapshot send failed: \(error.localizedDescription)"
                    }
                }
            )
        }
    }

    private func makeSnapshotData(player: Player, quests: [DailyQuest], activities: [ActivityLogEntry]) -> Data? {
        let todayStart = Calendar.current.startOfDay(for: Date())
        let todayCompleted = activities.filter {
            $0.type == .questCompleted && $0.timestamp >= todayStart
        }.count

        let questItems = quests
            .sorted { lhs, rhs in
                if lhs.status == .completed && rhs.status != .completed { return false }
                if lhs.status != .completed && rhs.status == .completed { return true }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            .map { quest in
                WatchQuestSnapshotItem(
                    id: quest.id.uuidString,
                    title: quest.title,
                    subtitle: quest.description,
                    status: quest.status.rawValue,
                    trackingType: quest.trackingType.rawValue,
                    progress: quest.currentProgress,
                    targetValue: quest.targetValue,
                    unit: quest.unit,
                    xpReward: quest.xpReward,
                    goldReward: quest.goldReward
                )
            }

        let snapshot = WatchStateSnapshot(
            generatedAt: Date(),
            playerName: player.name,
            level: player.level,
            currentXP: player.currentXP,
            xpRequiredForNextLevel: player.xpRequiredForNextLevel,
            gold: player.gold,
            currentHP: player.currentHP,
            maxHP: player.maxHP,
            completedToday: todayCompleted,
            totalQuests: quests.count,
            quests: questItems
        )

        return try? JSONEncoder().encode(snapshot)
    }

    private func currentSnapshotReply() -> [String: Any] {
        let data = latestSnapshotData ?? makeSnapshotData(
            player: GameEngine.shared.player,
            quests: GameEngine.shared.dailyQuests,
            activities: GameEngine.shared.recentActivity
        )

        var reply: [String: Any] = [schemaVersionKey: syncSchemaVersion]
        if let data {
            reply[snapshotContextKey] = data
        }
        return reply
    }

    private func handleCommandMessage(_ payload: [String: Any]) -> [String: Any] {
        guard let command = payload[commandKey] as? String else {
            return currentSnapshotReply().merging(["ok": false, "error": "Missing command"]) { _, new in new }
        }

        switch command {
        case "fetchSnapshot":
            return currentSnapshotReply().merging(["ok": true]) { _, new in new }

        case "completeQuest":
            guard let questIDString = payload[questIDKey] as? String,
                  let questID = UUID(uuidString: questIDString) else {
                return currentSnapshotReply().merging(["ok": false, "error": "Invalid quest ID"]) { _, new in new }
            }

            let result = completeQuestIfPossible(questID: questID)
            return currentSnapshotReply().merging(result) { _, new in new }

        default:
            return currentSnapshotReply().merging(["ok": false, "error": "Unsupported command"]) { _, new in new }
        }
    }

    private func handleBackgroundPayload(_ payload: [String: Any]) {
        if let questIDString = payload[questIDKey] as? String,
           let questID = UUID(uuidString: questIDString) {
            _ = completeQuestIfPossible(questID: questID)
        }

        if let queuedIDs = payload[queuedQuestIDsKey] as? [String] {
            for rawID in queuedIDs {
                if let questID = UUID(uuidString: rawID) {
                    _ = completeQuestIfPossible(questID: questID)
                }
            }
        }
    }

    private func completeQuestIfPossible(questID: UUID) -> [String: Any] {
        guard let quest = GameEngine.shared.dailyQuests.first(where: { $0.id == questID }) else {
            return ["ok": false, "error": "Quest not found"]
        }

        let result = GameEngine.shared.completeQuest(quest)
        if result.success {
            lastSyncDate = Date()
            lastSyncEvent = "Quest completed from watch: \(quest.title)"
            return [
                "ok": true,
                "completedQuestID": questID.uuidString,
                "message": result.message,
                "xpAwarded": result.xpAwarded,
                "goldAwarded": result.goldAwarded
            ]
        }

        return [
            "ok": false,
            "completedQuestID": questID.uuidString,
            "error": result.message
        ]
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            applySessionState(from: session)
            if let error {
                lastSyncEvent = "Watch activation failed: \(error.localizedDescription)"
                return
            }
            lastSyncEvent = "Watch session activated."
            if let latestSnapshotData {
                sendSnapshotContext(latestSnapshotData)
            } else {
                let snapshot = makeSnapshotData(
                    player: GameEngine.shared.player,
                    quests: GameEngine.shared.dailyQuests,
                    activities: GameEngine.shared.recentActivity
                )
                if let snapshot {
                    latestSnapshotData = snapshot
                    sendSnapshotContext(snapshot)
                }
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in
            applySessionState(from: session)
            lastSyncEvent = "Watch session became inactive."
        }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor in
            applySessionState(from: session)
            WCSession.default.activate()
            lastSyncEvent = "Watch session reactivating."
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            applySessionState(from: session)
            lastSyncEvent = session.isReachable ? "Watch became reachable." : "Watch is not reachable."
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            _ = handleCommandMessage(message)
            applySessionState(from: session)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor in
            let reply = handleCommandMessage(message)
            applySessionState(from: session)
            replyHandler(reply)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in
            handleBackgroundPayload(userInfo)
            applySessionState(from: session)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            handleBackgroundPayload(applicationContext)
            applySessionState(from: session)
        }
    }
}

// MARK: - Watch Snapshot Models

struct WatchStateSnapshot: Codable {
    let generatedAt: Date
    let playerName: String
    let level: Int
    let currentXP: Int
    let xpRequiredForNextLevel: Int
    let gold: Int
    let currentHP: Int
    let maxHP: Int
    let completedToday: Int
    let totalQuests: Int
    let quests: [WatchQuestSnapshotItem]
}

struct WatchQuestSnapshotItem: Codable {
    let id: String
    let title: String
    let subtitle: String
    let status: String
    let trackingType: String
    let progress: Double
    let targetValue: Double
    let unit: String
    let xpReward: Int
    let goldReward: Int
}
