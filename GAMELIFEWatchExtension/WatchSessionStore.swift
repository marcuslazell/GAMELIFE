import Foundation
import WatchConnectivity

@MainActor
final class WatchSessionStore: NSObject, ObservableObject {

    @Published private(set) var snapshot: WatchStateSnapshot?
    @Published private(set) var isSessionSupported = WCSession.isSupported()
    @Published private(set) var isReachable = false
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var statusMessage = "Connecting to iPhone..."
    @Published private(set) var pendingCompletionQuestIDs: Set<String> = []

    private let snapshotContextKey = "snapshotData"
    private let messageTypeKey = "type"
    private let commandKey = "command"
    private let questIDKey = "questID"
    private let queuedQuestIDsKey = "queuedCompleteQuestIDs"

    private lazy var session: WCSession = .default

    override init() {
        super.init()
        activateSessionIfPossible()
    }

    func activateSessionIfPossible() {
        guard WCSession.isSupported() else {
            isSessionSupported = false
            statusMessage = "Watch sync is unavailable on this device."
            return
        }

        session.delegate = self
        session.activate()
        applySessionState(from: session)

        if let contextData = session.receivedApplicationContext[snapshotContextKey] as? Data {
            applySnapshotData(contextData, source: "application context")
        }

        refreshSnapshot()
    }

    func refreshSnapshot() {
        guard WCSession.isSupported() else { return }

        let payload: [String: Any] = [
            commandKey: "fetchSnapshot",
            messageTypeKey: "snapshot"
        ]

        if session.isReachable {
            session.sendMessage(payload, replyHandler: { [weak self] reply in
                Task { @MainActor in
                    self?.handleReplyPayload(reply)
                }
            }, errorHandler: { [weak self] error in
                Task { @MainActor in
                    self?.statusMessage = "Refresh failed: \(error.localizedDescription)"
                }
            })
        } else {
            statusMessage = "Waiting for iPhone connection."
        }
    }

    func completeQuest(_ quest: WatchQuestSnapshotItem) {
        guard !quest.isCompleted else { return }

        let payload: [String: Any] = [
            commandKey: "completeQuest",
            questIDKey: quest.id
        ]

        pendingCompletionQuestIDs.insert(quest.id)

        if session.isReachable {
            session.sendMessage(payload, replyHandler: { [weak self] reply in
                Task { @MainActor in
                    self?.handleCompletionReply(reply, questID: quest.id)
                }
            }, errorHandler: { [weak self] error in
                Task { @MainActor in
                    self?.pendingCompletionQuestIDs.remove(quest.id)
                    self?.statusMessage = "Could not complete quest: \(error.localizedDescription)"
                }
            })
        } else {
            session.transferUserInfo([queuedQuestIDsKey: [quest.id]])
            statusMessage = "Quest queued. Will sync when iPhone is reachable."
        }
    }

    private func handleCompletionReply(_ reply: [String: Any], questID: String) {
        pendingCompletionQuestIDs.remove(questID)

        if let snapshotData = reply[snapshotContextKey] as? Data {
            applySnapshotData(snapshotData, source: "completion reply")
        }

        let ok = (reply["ok"] as? Bool) ?? false
        if ok {
            statusMessage = (reply["message"] as? String) ?? "Quest completed."
        } else {
            statusMessage = (reply["error"] as? String) ?? "Quest completion failed."
        }
    }

    private func handleReplyPayload(_ payload: [String: Any]) {
        if let snapshotData = payload[snapshotContextKey] as? Data {
            applySnapshotData(snapshotData, source: "reply")
        } else {
            statusMessage = "No snapshot received from iPhone."
        }
    }

    private func applySnapshotData(_ data: Data, source: String) {
        do {
            let decoded = try JSONDecoder().decode(WatchStateSnapshot.self, from: data)
            snapshot = decoded
            lastSyncDate = Date()
            statusMessage = "Synced via \(source)."

            let availableIDs = Set(decoded.quests.map(\.id))
            pendingCompletionQuestIDs = pendingCompletionQuestIDs.filter { availableIDs.contains($0) }
        } catch {
            statusMessage = "Snapshot decode failed: \(error.localizedDescription)"
        }
    }

    private func applySessionState(from session: WCSession) {
        isSessionSupported = WCSession.isSupported()
        isReachable = session.isReachable
    }
}

extension WatchSessionStore: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            applySessionState(from: session)
            if let error {
                statusMessage = "Activation failed: \(error.localizedDescription)"
            } else {
                statusMessage = "Watch session activated."
                if let contextData = session.receivedApplicationContext[snapshotContextKey] as? Data {
                    applySnapshotData(contextData, source: "application context")
                } else {
                    refreshSnapshot()
                }
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            applySessionState(from: session)
            if session.isReachable {
                statusMessage = "iPhone reachable."
                refreshSnapshot()
            } else {
                statusMessage = "Waiting for iPhone connection."
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[snapshotContextKey] as? Data else { return }
        Task { @MainActor in
            applySnapshotData(data, source: "application context")
            applySessionState(from: session)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let data = message[snapshotContextKey] as? Data else { return }
        Task { @MainActor in
            applySnapshotData(data, source: "message")
            applySessionState(from: session)
        }
    }
}

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

struct WatchQuestSnapshotItem: Codable, Identifiable {
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

    var isCompleted: Bool {
        status.lowercased() == "completed"
    }

    var progressFraction: Double {
        guard targetValue > 0 else {
            return isCompleted ? 1 : 0
        }

        return min(max(progress / targetValue, 0), 1)
    }

    var progressText: String {
        if targetValue > 0 {
            let currentValue = Int(progress.rounded())
            let target = Int(targetValue.rounded())
            return "\(currentValue)/\(target) \(unit)"
        }

        return isCompleted ? "Completed" : "In progress"
    }
}
