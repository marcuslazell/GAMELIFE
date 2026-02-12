//
//  CloudKitSyncManager.swift
//  GAMELIFE
//
//  Keeps game state synchronized across Apple devices using CloudKit.
//

import Foundation
import CloudKit
import Combine

@MainActor
final class CloudKitSyncManager: ObservableObject {

    static let shared = CloudKitSyncManager()

    @Published private(set) var isCloudKitAvailable = false
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var lastSyncEvent = "Cloud sync idle."

    private let container: CKContainer
    private let database: CKDatabase
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let defaults = UserDefaults.standard

    private let recordType = "GameStateSnapshot"
    private let payloadField = "payload"
    private let updatedAtField = "updatedAt"
    private let schemaField = "schemaVersion"
    private let deviceField = "deviceID"
    private let schemaVersion = 1
    private let uploadDebounceSeconds: TimeInterval = 1.5
    private let remoteClockTolerance: TimeInterval = 1.0
    private let maxSnapshotsToKeep = 25

    private let localStateUpdatedAtKey = "gamelife_local_state_updated_at"
    private let cloudSyncDeviceIDKey = "gamelife_cloud_sync_device_id"
    private let cloudUploadMuteUntilKey = "gamelife_cloud_upload_mute_until"

    private var didStart = false
    private var uploadWorkItem: DispatchWorkItem?
    private var lastQueuedPayloadData: Data?

    private init(container: CKContainer = .default()) {
        self.container = container
        self.database = container.privateCloudDatabase
    }

    func start() {
        guard !didStart else { return }
        didStart = true

        Task { @MainActor [weak self] in
            await self?.refreshAvailability()
        }
    }

    func queueUpload(
        player: Player,
        dailyQuests: [DailyQuest],
        bossFights: [BossFight],
        recentActivity: [ActivityLogEntry]
    ) {
        guard isCloudKitAvailable else { return }
        guard !uploadsMuted else { return }

        let snapshot = CloudGameStateSnapshot(
            schemaVersion: schemaVersion,
            updatedAt: Date(),
            deviceID: deviceID,
            player: player,
            dailyQuests: dailyQuests,
            bossFights: bossFights,
            recentActivity: recentActivity,
            questHistory: QuestDataManager.shared.loadQuestHistory(),
            trackedLocations: LocationDataManager.shared.loadLocations()
        )

        guard let payloadData = try? encoder.encode(snapshot) else {
            lastSyncEvent = "Cloud snapshot encoding failed."
            return
        }

        if payloadData == lastQueuedPayloadData {
            return
        }
        lastQueuedPayloadData = payloadData

        uploadWorkItem?.cancel()
        let uploadJob = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                await self?.performUpload(snapshot: snapshot, payloadData: payloadData)
            }
        }
        uploadWorkItem = uploadJob
        DispatchQueue.main.asyncAfter(deadline: .now() + uploadDebounceSeconds, execute: uploadJob)
    }

    func fetchLatestSnapshotIfNewer(force: Bool = false) async -> CloudGameStateSnapshot? {
        if !didStart {
            start()
        }
        if !isCloudKitAvailable {
            await refreshAvailability()
        }
        guard isCloudKitAvailable else { return nil }

        do {
            guard let record = try await fetchLatestRecord() else {
                return nil
            }

            guard let payloadData = record[payloadField] as? Data else {
                lastSyncEvent = "Cloud snapshot payload missing."
                return nil
            }

            let snapshot = try decoder.decode(CloudGameStateSnapshot.self, from: payloadData)

            if !force, let localDate = localStateUpdatedAt {
                if snapshot.updatedAt <= localDate.addingTimeInterval(remoteClockTolerance) {
                    return nil
                }
            }

            return snapshot
        } catch {
            lastSyncEvent = "Cloud fetch failed: \(error.localizedDescription)"
            return nil
        }
    }

    func markLocalStateApplied(at date: Date) {
        defaults.set(date, forKey: localStateUpdatedAtKey)
        // Prevent immediate upload bounce when applying remote state.
        defaults.set(Date().addingTimeInterval(2.0), forKey: cloudUploadMuteUntilKey)
    }

    var localStateUpdatedAt: Date? {
        defaults.object(forKey: localStateUpdatedAtKey) as? Date
    }

    // MARK: - Private

    private var deviceID: String {
        if let existing = defaults.string(forKey: cloudSyncDeviceIDKey), !existing.isEmpty {
            return existing
        }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: cloudSyncDeviceIDKey)
        return generated
    }

    private var uploadsMuted: Bool {
        guard let muteUntil = defaults.object(forKey: cloudUploadMuteUntilKey) as? Date else {
            return false
        }
        return Date() < muteUntil
    }

    private func refreshAvailability() async {
        do {
            let status = try await accountStatus()
            isCloudKitAvailable = (status == .available)
            if status == .available {
                lastSyncEvent = "CloudKit available."
            } else {
                lastSyncEvent = "CloudKit unavailable (\(status.rawValue))."
            }
        } catch {
            isCloudKitAvailable = false
            lastSyncEvent = "CloudKit account check failed: \(error.localizedDescription)"
        }
    }

    private func accountStatus() async throws -> CKAccountStatus {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKAccountStatus, Error>) in
            container.accountStatus { status, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: status)
            }
        }
    }

    private func performUpload(snapshot: CloudGameStateSnapshot, payloadData: Data) async {
        guard isCloudKitAvailable else { return }
        guard !uploadsMuted else { return }

        let record = CKRecord(recordType: recordType)
        record[payloadField] = payloadData as CKRecordValue
        record[updatedAtField] = snapshot.updatedAt as CKRecordValue
        record[schemaField] = Int64(schemaVersion) as CKRecordValue
        record[deviceField] = deviceID as CKRecordValue

        do {
            try await saveRecord(record)
            markLocalStateApplied(at: snapshot.updatedAt)
            lastSyncDate = Date()
            lastSyncEvent = "Cloud snapshot uploaded."
            Task { @MainActor [weak self] in
                await self?.pruneOldSnapshots()
            }
        } catch {
            lastSyncEvent = "Cloud upload failed: \(error.localizedDescription)"
        }
    }

    private func saveRecord(_ record: CKRecord) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            database.save(record) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: ())
            }
        }
    }

    private func fetchLatestRecord() async throws -> CKRecord? {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: updatedAtField, ascending: false)]

        let records = try await performQuery(query: query, limit: 1)
        return records.first
    }

    private func pruneOldSnapshots() async {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: updatedAtField, ascending: false)]

        do {
            let records = try await performQuery(query: query, limit: maxSnapshotsToKeep + 10)
            guard records.count > maxSnapshotsToKeep else { return }
            let staleIDs = records.dropFirst(maxSnapshotsToKeep).map(\.recordID)
            try await deleteRecords(ids: staleIDs)
        } catch {
            // Cleanup failures are non-fatal.
        }
    }

    private func performQuery(query: CKQuery, limit: Int) async throws -> [CKRecord] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[CKRecord], Error>) in
            var fetched: [CKRecord] = []
            let lock = NSLock()

            let operation = CKQueryOperation(query: query)
            operation.resultsLimit = limit
            operation.recordMatchedBlock = { _, result in
                if case .success(let record) = result {
                    lock.lock()
                    fetched.append(record)
                    lock.unlock()
                }
            }
            operation.queryResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: fetched)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            database.add(operation)
        }
    }

    private func deleteRecords(ids: [CKRecord.ID]) async throws {
        guard !ids.isEmpty else { return }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: ids)
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: ())
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }
}

struct CloudGameStateSnapshot: Codable {
    let schemaVersion: Int
    let updatedAt: Date
    let deviceID: String
    let player: Player
    let dailyQuests: [DailyQuest]
    let bossFights: [BossFight]
    let recentActivity: [ActivityLogEntry]
    let questHistory: [QuestHistoryRecord]
    let trackedLocations: [TrackedLocation]
}
