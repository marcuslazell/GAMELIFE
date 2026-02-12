//
//  PermissionManager.swift
//  GAMELIFE
//
//  [SYSTEM]: Neural Link status monitor active.
//  System connections await your authorization.
//

import Foundation
import SwiftUI
import Combine
import HealthKit
import CoreLocation
import FamilyControls
import UserNotifications

// MARK: - Permission Manager

/// Unified manager for all app permissions
/// Follows the "Neural Link" approach - no permission bombing, user-initiated only
@MainActor
class PermissionManager: ObservableObject {

    static let shared = PermissionManager()

    // MARK: - Published Permission States

    @Published var healthKitEnabled = false
    @Published var screenTimeEnabled = false
    @Published var locationEnabled = false
    @Published var notificationsEnabled = false

    // Detailed status
    @Published var healthKitStatus: PermissionStatus = .notDetermined
    @Published var screenTimeStatus: PermissionStatus = .notDetermined
    @Published var locationStatus: PermissionStatus = .notDetermined
    @Published var notificationStatus: PermissionStatus = .notDetermined

    // MARK: - Private Properties

    private let healthStore = HKHealthStore()
    private let notificationCenter = UNUserNotificationCenter.current()
    private var cancellables = Set<AnyCancellable>()
    private var healthProbeTypes: [HKObjectType] {
        [
            HKQuantityType(.stepCount),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.appleExerciseTime),
            HKQuantityType(.appleStandTime),
            HKQuantityType(.dietaryWater),
            HKQuantityType(.bodyMass),
            HKQuantityType(.bodyFatPercentage),
            HKCategoryType(.sleepAnalysis),
            HKCategoryType(.mindfulSession),
            HKWorkoutType.workoutType()
        ]
    }

    // MARK: - Initialization

    private init() {
        observeLocationAuthorization()
        Task {
            await checkAllPermissions()
        }
    }

    private func observeLocationAuthorization() {
        NotificationCenter.default
            .publisher(for: .locationAuthorizationChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.checkLocationStatus()
            }
            .store(in: &cancellables)
    }

    // MARK: - Check All Permissions

    func checkAllPermissions() async {
        await checkHealthKitStatus()
        await checkScreenTimeStatus()
        checkLocationStatus()
        await checkNotificationStatus()
    }

    // MARK: - HealthKit

    func checkHealthKitStatus() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            healthKitStatus = .unavailable
            healthKitEnabled = false
            return
        }

        await HealthKitManager.shared.refreshAuthorizationStatus()
        if HealthKitManager.shared.isAuthorized {
            healthKitStatus = .authorized
            healthKitEnabled = true
            return
        }

        let statuses = healthProbeTypes.map { healthStore.authorizationStatus(for: $0) }
        let requestStatus = await authorizationRequestStatus()

        if statuses.contains(.sharingAuthorized) {
            healthKitStatus = .authorized
            healthKitEnabled = true
        } else if requestStatus == .shouldRequest || statuses.allSatisfy({ $0 == .notDetermined }) {
            healthKitStatus = .notDetermined
            healthKitEnabled = false
        } else if statuses.contains(.sharingDenied) || requestStatus == .unnecessary {
            healthKitStatus = .denied
            healthKitEnabled = false
        } else {
            healthKitStatus = .notDetermined
            healthKitEnabled = false
        }
    }

    func requestHealthKit() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw PermissionError.unavailable
        }

        guard hasNonEmptyInfoPlistValue("NSHealthShareUsageDescription") else {
            throw PermissionError.misconfigured("Missing NSHealthShareUsageDescription in Info.plist.")
        }

        do {
            try await HealthKitManager.shared.requestAuthorization()
            await checkHealthKitStatus()
        } catch {
            throw PermissionError.denied
        }
    }

    // MARK: - Screen Time

    func checkScreenTimeStatus() async {
        let center = AuthorizationCenter.shared

        switch center.authorizationStatus {
        case .approved:
            screenTimeStatus = .authorized
            screenTimeEnabled = true
            ScreenTimeManager.shared.startUsageMonitoring()
        case .denied:
            screenTimeStatus = .denied
            screenTimeEnabled = false
        case .notDetermined:
            screenTimeStatus = .notDetermined
            screenTimeEnabled = false
        @unknown default:
            screenTimeStatus = .notDetermined
            screenTimeEnabled = false
        }
    }

    func requestScreenTime() async throws {
        do {
            try await ScreenTimeManager.shared.requestAuthorization()
            ScreenTimeManager.shared.startUsageMonitoring()
            await checkScreenTimeStatus()
        } catch {
            await checkScreenTimeStatus()
            throw PermissionError.denied
        }
    }

    // MARK: - Location

    func checkLocationStatus() {
        switch CLLocationManager.authorizationStatus() {
        case .authorizedAlways:
            locationStatus = .authorized
            locationEnabled = true
        case .authorizedWhenInUse:
            locationStatus = .authorized
            locationEnabled = true
        case .denied, .restricted:
            locationStatus = .denied
            locationEnabled = false
        case .notDetermined:
            locationStatus = .notDetermined
            locationEnabled = false
        @unknown default:
            locationStatus = .notDetermined
            locationEnabled = false
        }
    }

    func requestLocation() {
        if locationStatus == .denied {
            openSystemSettings()
            return
        }
        LocationManager.shared.requestAuthorization()
        checkLocationStatus()

        // Re-check shortly after prompt interaction resolves.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.checkLocationStatus()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.checkLocationStatus()
        }
    }

    // MARK: - Notifications

    func checkNotificationStatus() async {
        let settings = await notificationCenter.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional:
            notificationStatus = .authorized
            notificationsEnabled = true
        case .denied:
            notificationStatus = .denied
            notificationsEnabled = false
        case .notDetermined:
            notificationStatus = .notDetermined
            notificationsEnabled = false
        case .ephemeral:
            notificationStatus = .authorized
            notificationsEnabled = true
        @unknown default:
            notificationStatus = .notDetermined
            notificationsEnabled = false
        }
    }

    func requestNotifications() async throws {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            await checkNotificationStatus()

            if !granted {
                throw PermissionError.denied
            }
        } catch {
            throw PermissionError.denied
        }
    }

    // MARK: - Settings Navigation

    func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    func openHealthApp() {
        guard let healthURL = URL(string: "x-apple-health://") else {
            openSystemSettings()
            return
        }

        UIApplication.shared.open(healthURL, options: [:]) { success in
            if !success {
                self.openSystemSettings()
            }
        }
    }

    private func hasNonEmptyInfoPlistValue(_ key: String) -> Bool {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return false
        }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func authorizationRequestStatus() async -> HKAuthorizationRequestStatus {
        await withCheckedContinuation { continuation in
            healthStore.getRequestStatusForAuthorization(
                toShare: [],
                read: Set(healthProbeTypes)
            ) { status, _ in
                continuation.resume(returning: status)
            }
        }
    }

    // MARK: - Neural Link Names

    func neuralLinkName(for permission: NeuralLinkType) -> String {
        switch permission {
        case .vitalSigns: return "Vital Signs"
        case .mindActivity: return "Mind Activity"
        case .worldPosition: return "World Position"
        case .systemMessages: return "System Messages"
        }
    }

    func neuralLinkDescription(for permission: NeuralLinkType) -> String {
        switch permission {
        case .vitalSigns: return "Connect to HealthKit for automatic progress tracking"
        case .mindActivity: return "Connect to Screen Time for app usage tracking"
        case .worldPosition: return "Connect to Location for geofence-based quests"
        case .systemMessages: return "Receive alerts and quest reminders"
        }
    }

    func neuralLinkIcon(for permission: NeuralLinkType) -> String {
        switch permission {
        case .vitalSigns: return "heart.fill"
        case .mindActivity: return "brain.head.profile"
        case .worldPosition: return "location.fill"
        case .systemMessages: return "bell.fill"
        }
    }

    func status(for permission: NeuralLinkType) -> PermissionStatus {
        switch permission {
        case .vitalSigns: return healthKitStatus
        case .mindActivity: return screenTimeStatus
        case .worldPosition: return locationStatus
        case .systemMessages: return notificationStatus
        }
    }

    func isEnabled(for permission: NeuralLinkType) -> Bool {
        switch permission {
        case .vitalSigns: return healthKitEnabled
        case .mindActivity: return screenTimeEnabled
        case .worldPosition: return locationEnabled
        case .systemMessages: return notificationsEnabled
        }
    }
}

// MARK: - Neural Link Type

enum NeuralLinkType: String, CaseIterable, Identifiable {
    case vitalSigns = "Vital Signs"
    case mindActivity = "Mind Activity"
    case worldPosition = "World Position"
    case systemMessages = "System Messages"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .vitalSigns: return SystemTheme.statVitality
        case .mindActivity: return SystemTheme.statIntelligence
        case .worldPosition: return SystemTheme.statAgility
        case .systemMessages: return SystemTheme.primaryBlue
        }
    }
}

// MARK: - Permission Status

enum PermissionStatus: String {
    case notDetermined = "Not Connected"
    case authorized = "Connected"
    case denied = "Denied"
    case unavailable = "Unavailable"

    var color: Color {
        switch self {
        case .notDetermined: return SystemTheme.textTertiary
        case .authorized: return SystemTheme.successGreen
        case .denied: return SystemTheme.criticalRed
        case .unavailable: return SystemTheme.textTertiary
        }
    }

    var icon: String {
        switch self {
        case .notDetermined: return "circle.dashed"
        case .authorized: return "checkmark.circle.fill"
        case .denied: return "xmark.circle.fill"
        case .unavailable: return "nosign"
        }
    }
}

// MARK: - Permission Error

enum PermissionError: Error, LocalizedError {
    case denied
    case unavailable
    case unknown
    case misconfigured(String)

    var errorDescription: String? {
        switch self {
        case .denied: return "Permission was denied"
        case .unavailable: return "Feature not available on this device"
        case .unknown: return "An unknown error occurred"
        case .misconfigured(let message): return message
        }
    }
}
