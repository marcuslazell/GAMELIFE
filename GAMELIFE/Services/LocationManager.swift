//
//  LocationManager.swift
//  GAMELIFE
//
//  [SYSTEM]: World position tracker initialized.
//  Your movements through the realm are now monitored.
//

import Foundation
import CoreLocation
import Combine

// MARK: - Location Manager

/// Manages Core Location for geofence-based quest tracking
/// Tracks: Gym visits, library visits, outdoor time, custom locations
@MainActor
class LocationManager: NSObject, ObservableObject {

    static let shared = LocationManager()

    private let locationManager = CLLocationManager()
    private var geofenceRegions: [CLCircularRegion] = []
    private var regionEntryTimes: [String: Date] = [:]
    private var lastPublishedLocation: CLLocation?
    private var lastManualRefreshRequestDate: Date?

    // MARK: - Published Properties

    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isAuthorized = false
    @Published var hasBackgroundAuthorization = false
    @Published var currentLocation: CLLocation?
    @Published var activeGeofences: [TrackedLocation] = []
    @Published var lastTrackingEventDate: Date?
    @Published var lastTrackingEventMessage: String = "No location events yet."

    // Visit tracking
    @Published var gymVisitToday: LocationVisit?
    @Published var outdoorMinutesToday: Int = 0

    // MARK: - Initialization

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.distanceFilter = 25
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = false
        locationManager.activityType = .fitness

        checkAuthorizationStatus()
        startLocationUpdatesIfAuthorized()
    }

    // MARK: - Authorization

    func requestAuthorization() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            // Escalate to Always to keep location-based quests reliable in background.
            locationManager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    /// Trigger an on-demand location refresh (used by pull-to-refresh in Quests).
    func requestSingleLocationRefresh() {
        guard isAuthorized else { return }
        if let lastRequest = lastManualRefreshRequestDate,
           Date().timeIntervalSince(lastRequest) < 3 {
            return
        }
        lastManualRefreshRequestDate = Date()
        locationManager.requestLocation()
    }

    private func checkAuthorizationStatus() {
        authorizationStatus = locationManager.authorizationStatus
        isAuthorized = authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse
        hasBackgroundAuthorization = authorizationStatus == .authorizedAlways
    }

    private func startLocationUpdatesIfAuthorized() {
        guard isAuthorized else {
            locationManager.allowsBackgroundLocationUpdates = false
            locationManager.showsBackgroundLocationIndicator = false
            locationManager.stopUpdatingLocation()
            locationManager.stopMonitoringSignificantLocationChanges()
            return
        }

        configureBackgroundLocationUpdates()
        if activeGeofences.isEmpty {
            locationManager.stopUpdatingLocation()
        } else {
            locationManager.startUpdatingLocation()
        }
        if authorizationStatus == .authorizedAlways {
            locationManager.startMonitoringSignificantLocationChanges()
        } else {
            locationManager.stopMonitoringSignificantLocationChanges()
        }
    }

    // MARK: - Geofencing

    /// Add a geofence for a tracked location (gym, library, etc.)
    func addGeofence(for location: TrackedLocation) {
        if !activeGeofences.contains(where: { $0.id == location.id }) {
            activeGeofences.append(location)
        }

        guard isAuthorized else {
            print("[SYSTEM] Location permission required before adding geofences")
            return
        }

        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            print("[SYSTEM] Geofencing not available on this device")
            return
        }

        let sanitizedRadius = max(50, min(location.radius, 1000))

        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(
                latitude: location.latitude,
                longitude: location.longitude
            ),
            radius: sanitizedRadius,
            identifier: location.id.uuidString
        )

        if geofenceRegions.contains(where: { $0.identifier == region.identifier }) {
            return
        }

        region.notifyOnEntry = true
        region.notifyOnExit = true

        locationManager.startMonitoring(for: region)
        geofenceRegions.append(region)
        recordTrackingEvent("Geofence active: \(location.name)")
        startLocationUpdatesIfAuthorized()

        print("[SYSTEM] Geofence added: \(location.name)")
    }

    /// Register a geofence tied directly to a location-tracked quest.
    func upsertQuestGeofence(for quest: DailyQuest) {
        guard quest.trackingType == .location,
              let coordinate = quest.locationCoordinate else {
            removeQuestGeofence(for: quest.id)
            return
        }

        removeQuestGeofence(for: quest.id)

        let configuredMinimumStay: Int = {
            // Legacy "visits" quests are migrated to a 45-minute stay requirement.
            if quest.unit == "visits" && quest.targetValue <= 1 {
                return 45
            }
            return max(5, Int(quest.targetValue.rounded()))
        }()

        let trackedLocation = TrackedLocation(
            name: coordinate.locationName,
            type: .custom,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            radius: coordinate.radius,
            minimumVisitMinutes: configuredMinimumStay,
            statContribution: quest.targetStats.first ?? .agility,
            xpReward: quest.xpReward,
            questID: quest.id
        )

        addGeofence(for: trackedLocation)

        if let currentLocation {
            let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            if currentLocation.distance(from: target) <= coordinate.radius {
                // If the user is already in-range, begin dwell tracking from now.
                regionEntryTimes[trackedLocation.id.uuidString] = Date()
            }
        }
    }

    /// Remove a quest-specific geofence.
    func removeQuestGeofence(for questID: UUID) {
        let matches = activeGeofences.filter { $0.questID == questID }
        for location in matches {
            removeGeofence(for: location)
        }
    }

    /// Remove a geofence
    func removeGeofence(for location: TrackedLocation) {
        if let region = geofenceRegions.first(where: { $0.identifier == location.id.uuidString }) {
            locationManager.stopMonitoring(for: region)
            geofenceRegions.removeAll { $0.identifier == location.id.uuidString }
            activeGeofences.removeAll { $0.id == location.id }
            recordTrackingEvent("Geofence removed: \(location.name)")
            startLocationUpdatesIfAuthorized()
        }
    }

    /// Remove all geofences
    func removeAllGeofences() {
        for region in geofenceRegions {
            locationManager.stopMonitoring(for: region)
        }
        geofenceRegions.removeAll()
        activeGeofences.removeAll()
        regionEntryTimes.removeAll()
        startLocationUpdatesIfAuthorized()
    }

    // MARK: - Visit Tracking

    /// Check if user has been at a location for minimum duration
    func checkVisitDuration(locationId: String, minimumMinutes: Int) -> Bool {
        guard let entryTime = regionEntryTimes[locationId] else { return false }

        let duration = Date().timeIntervalSince(entryTime)
        return duration >= TimeInterval(minimumMinutes * 60)
    }

    /// Get current visit duration in minutes
    func getCurrentVisitDuration(locationId: String) -> Int {
        guard let entryTime = regionEntryTimes[locationId] else { return 0 }
        return Int(Date().timeIntervalSince(entryTime) / 60)
    }

    // MARK: - Quest Integration

    enum QuestTrackingStatus: Equatable {
        case completed
        case permissionRequired
        case invalidAddress
        case monitoringUnavailable
        case notMonitoring
        case monitoring(locationName: String)
        case inRange(minutes: Int, requiredMinutes: Int)
    }

    /// Returns a user-facing tracking state for location-based quests so the UI
    /// can show whether monitoring is active and progressing.
    func questTrackingStatus(for quest: DailyQuest) -> QuestTrackingStatus {
        guard quest.trackingType == .location else { return .notMonitoring }
        if quest.status == .completed { return .completed }
        guard quest.locationCoordinate != nil else { return .invalidAddress }
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            return .monitoringUnavailable
        }
        guard isAuthorized else { return .permissionRequired }

        guard let trackedLocation = activeGeofences.first(where: { $0.questID == quest.id }) else {
            return .notMonitoring
        }

        guard let currentLocation else {
            return .monitoring(locationName: trackedLocation.name)
        }

        let target = CLLocation(latitude: trackedLocation.latitude, longitude: trackedLocation.longitude)
        let isInside = currentLocation.distance(from: target) <= trackedLocation.radius
        guard isInside else {
            return .monitoring(locationName: trackedLocation.name)
        }

        let entryTime = regionEntryTimes[trackedLocation.id.uuidString] ?? Date()
        let minutes = Int(Date().timeIntervalSince(entryTime) / 60)
        return .inRange(
            minutes: max(0, minutes),
            requiredMinutes: trackedLocation.minimumVisitMinutes
        )
    }

    /// Returns live 0...1 progress for location quests based on in-radius dwell time.
    /// This lets UI progress bars fill over time while the user remains at the address.
    func liveLocationProgress(for quest: DailyQuest, now: Date = Date()) -> Double {
        guard quest.trackingType == .location else { return 0 }
        if quest.status == .completed { return 1 }
        guard isAuthorized else { return 0 }

        guard let trackedLocation = activeGeofences.first(where: { $0.questID == quest.id }) else {
            return 0
        }

        guard let currentLocation else { return 0 }

        let target = CLLocation(latitude: trackedLocation.latitude, longitude: trackedLocation.longitude)
        let isInside = currentLocation.distance(from: target) <= trackedLocation.radius
        guard isInside else { return 0 }

        let identifier = trackedLocation.id.uuidString
        if regionEntryTimes[identifier] == nil {
            regionEntryTimes[identifier] = now
            return 0
        }

        guard let entryTime = regionEntryTimes[identifier] else { return 0 }
        let elapsedMinutes = now.timeIntervalSince(entryTime) / 60.0
        let requiredMinutes = max(1, trackedLocation.minimumVisitMinutes)
        return min(1, max(0, elapsedMinutes / Double(requiredMinutes)))
    }

    /// Calculate AGI XP based on location activity (promptness, movement)
    func calculateAgilityXP() -> Int {
        // XP for gym visits
        var xp = 0

        if let gymVisit = gymVisitToday, gymVisit.durationMinutes >= 30 {
            xp += 20 // Bonus for 30+ min gym visit
        }

        // XP for outdoor time
        xp += outdoorMinutesToday / 10 // 1 XP per 10 minutes outside

        return xp
    }

    /// Create a gym visit geofence
    func setupGymGeofence(name: String, latitude: Double, longitude: Double) -> TrackedLocation {
        let gymLocation = TrackedLocation(
            name: name,
            type: .gym,
            latitude: latitude,
            longitude: longitude,
            radius: 100, // 100 meter radius
            minimumVisitMinutes: 30,
            statContribution: .strength,
            xpReward: 30
        )

        addGeofence(for: gymLocation)
        return gymLocation
    }

    /// Create a library/study location geofence
    func setupLibraryGeofence(name: String, latitude: Double, longitude: Double) -> TrackedLocation {
        let libraryLocation = TrackedLocation(
            name: name,
            type: .library,
            latitude: latitude,
            longitude: longitude,
            radius: 50,
            minimumVisitMinutes: 60,
            statContribution: .intelligence,
            xpReward: 40
        )

        addGeofence(for: libraryLocation)
        return libraryLocation
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        locationManager(manager, didChangeAuthorization: manager.authorizationStatus)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
            self.authorizationStatus = status
            self.isAuthorized = status == .authorizedAlways || status == .authorizedWhenInUse
            self.hasBackgroundAuthorization = status == .authorizedAlways
            self.startLocationUpdatesIfAuthorized()

            if self.isAuthorized {
                // Re-register geofences after authorization
                for location in self.activeGeofences {
                    self.addGeofence(for: location)
                }
            }

            NotificationCenter.default.post(name: .locationAuthorizationChanged, object: status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        Task { @MainActor in
            if self.shouldPublishLocation(location) {
                self.currentLocation = location
                self.lastPublishedLocation = location
            }
            await self.evaluateActiveGeofenceVisits(at: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            let nsError = error as NSError
            if nsError.domain == kCLErrorDomain {
                // kCLErrorDomain code 0 (locationUnknown) is transient and noisy,
                // especially in simulator / temporary GPS stalls.
                if nsError.code == CLError.locationUnknown.rawValue || nsError.code == 0 {
                    return
                }

                if nsError.code == CLError.denied.rawValue {
                    self.recordTrackingEvent("Location permission denied.")
                    return
                }
            }

            // requestLocation() requires this delegate path; handle it gracefully
            // so pull-to-refresh cannot terminate the app on transient failures.
            self.recordTrackingEvent("Location refresh failed: \(error.localizedDescription)")
            print("[SYSTEM] Location update failed: \(error.localizedDescription)")
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let circularRegion = region as? CLCircularRegion else { return }

        Task { @MainActor in
            // Record entry time
            self.regionEntryTimes[circularRegion.identifier] = Date()

            // Find the tracked location
            if let trackedLocation = self.activeGeofences.first(where: { $0.id.uuidString == circularRegion.identifier }) {
                print("[SYSTEM] Entered region: \(trackedLocation.name)")
                self.recordTrackingEvent("Entered \(trackedLocation.name)")

                // Send notification
                NotificationManager.shared.sendLocationArrivalNotification(location: trackedLocation)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let circularRegion = region as? CLCircularRegion else { return }

        Task { @MainActor in
            // Calculate visit duration
            if let entryTime = self.regionEntryTimes[circularRegion.identifier],
               let trackedLocation = self.activeGeofences.first(where: { $0.id.uuidString == circularRegion.identifier }) {

                let duration = Date().timeIntervalSince(entryTime)
                let durationMinutes = Int(duration / 60)

                print("[SYSTEM] Exited region: \(trackedLocation.name) after \(durationMinutes) minutes")
                self.recordTrackingEvent("Exited \(trackedLocation.name) after \(durationMinutes)m")

                // Create visit record
                let visit = LocationVisit(
                    location: trackedLocation,
                    entryTime: entryTime,
                    exitTime: Date(),
                    durationMinutes: durationMinutes
                )

                // Check if visit qualifies for quest completion
                if durationMinutes >= trackedLocation.minimumVisitMinutes {
                    // Award XP and complete quest
                    await self.handleSuccessfulVisit(visit)
                }

                // Store gym visit specifically
                if trackedLocation.type == .gym {
                    self.gymVisitToday = visit
                }
            }

            // Clear entry time
            self.regionEntryTimes.removeValue(forKey: circularRegion.identifier)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        print("[SYSTEM] Geofence monitoring failed: \(error.localizedDescription)")
    }

    // MARK: - Visit Handling

    @MainActor
    private func handleSuccessfulVisit(_ visit: LocationVisit) async {
        if let questID = visit.location.questID,
           let quest = GameEngine.shared.dailyQuests.first(where: { $0.id == questID }),
           quest.status == .completed {
            return
        }

        // Notify game manager to award XP
        let xp = visit.location.xpReward
        let stat = visit.location.statContribution

        // Post notification for quest system to pick up
        NotificationCenter.default.post(
            name: .locationVisitCompleted,
            object: nil,
            userInfo: {
                var payload: [String: Any] = [
                    "visit": visit,
                    "xp": xp,
                    "stat": stat
                ]
                if let questID = visit.location.questID {
                    payload["questID"] = questID
                }
                return payload
            }()
        )

        recordTrackingEvent("Location quest completed at \(visit.location.name)")

        // Completion notifications are emitted centrally by GameEngine.completeQuest
        // to avoid duplicate banners across tracking providers.
    }

    @MainActor
    private func evaluateActiveGeofenceVisits(at location: CLLocation) async {
        for trackedLocation in activeGeofences {
            guard trackedLocation.questID != nil else { continue }

            let regionIdentifier = trackedLocation.id.uuidString
            let target = CLLocation(latitude: trackedLocation.latitude, longitude: trackedLocation.longitude)
            let isInside = location.distance(from: target) <= trackedLocation.radius

            guard isInside else { continue }

            if regionEntryTimes[regionIdentifier] == nil {
                regionEntryTimes[regionIdentifier] = Date()
                recordTrackingEvent("In range: \(trackedLocation.name)")
                NotificationCenter.default.post(name: .geofenceEntered, object: trackedLocation)
                continue
            }

            guard let entryTime = regionEntryTimes[regionIdentifier] else { continue }
            let durationMinutes = Int(Date().timeIntervalSince(entryTime) / 60)
            guard durationMinutes >= trackedLocation.minimumVisitMinutes else { continue }

            let visit = LocationVisit(
                location: trackedLocation,
                entryTime: entryTime,
                exitTime: Date(),
                durationMinutes: durationMinutes
            )

            // Prevent duplicate completions while the user remains inside.
            regionEntryTimes.removeValue(forKey: regionIdentifier)
            await handleSuccessfulVisit(visit)
        }
    }

    var isMonitoringActive: Bool {
        isAuthorized && !activeGeofences.isEmpty && CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self)
    }

    private func recordTrackingEvent(_ message: String) {
        lastTrackingEventDate = Date()
        lastTrackingEventMessage = message
    }

    /// Avoid noisy UI jumps from tiny GPS drift while still evaluating geofence logic.
    private func shouldPublishLocation(_ location: CLLocation) -> Bool {
        guard location.horizontalAccuracy > 0 else { return false }
        guard let last = lastPublishedLocation else { return true }

        let movedMeters = location.distance(from: last)
        let accuracyImproved = location.horizontalAccuracy + 5 < last.horizontalAccuracy
        return movedMeters >= 20 || accuracyImproved
    }

    /// Enabling background location updates can assert if the app/runtime isn't
    /// background-location-capable (common in simulator/debug edge cases).
    /// We only enable it when "location" background mode is declared and we
    /// have Always authorization; geofence monitoring still works otherwise.
    private func configureBackgroundLocationUpdates() {
        let shouldEnableBackgroundUpdates =
            hasBackgroundAuthorization &&
            hasLocationBackgroundMode &&
            !isRunningInSimulator &&
            !activeGeofences.isEmpty

        locationManager.allowsBackgroundLocationUpdates = shouldEnableBackgroundUpdates
        locationManager.showsBackgroundLocationIndicator = shouldEnableBackgroundUpdates
    }

    private var hasLocationBackgroundMode: Bool {
        if let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] {
            return modes.contains("location")
        }

        if let singleMode = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? String {
            return singleMode
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .contains("location")
        }

        return false
    }

    private var isRunningInSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
}

// MARK: - Tracked Location

/// A location being tracked for geofence-based quests
struct TrackedLocation: Codable, Identifiable {
    let id: UUID
    let name: String
    let type: LocationType
    let latitude: Double
    let longitude: Double
    let radius: Double // in meters
    let minimumVisitMinutes: Int
    let statContribution: StatType
    let xpReward: Int
    let questID: UUID?

    enum LocationType: String, Codable {
        case gym = "Gym"
        case library = "Library"
        case office = "Office"
        case park = "Park"
        case custom = "Custom"

        var icon: String {
            switch self {
            case .gym: return "figure.strengthtraining.traditional"
            case .library: return "books.vertical.fill"
            case .office: return "building.2.fill"
            case .park: return "leaf.fill"
            case .custom: return "mappin.circle.fill"
            }
        }
    }

    init(
        name: String,
        type: LocationType,
        latitude: Double,
        longitude: Double,
        radius: Double = 100,
        minimumVisitMinutes: Int = 30,
        statContribution: StatType = .strength,
        xpReward: Int = 20,
        questID: UUID? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.minimumVisitMinutes = minimumVisitMinutes
        self.statContribution = statContribution
        self.xpReward = xpReward
        self.questID = questID
    }
}

// MARK: - Location Visit

/// Record of a completed location visit
struct LocationVisit: Codable {
    let id: UUID
    let location: TrackedLocation
    let entryTime: Date
    let exitTime: Date
    let durationMinutes: Int

    var metMinimumDuration: Bool {
        durationMinutes >= location.minimumVisitMinutes
    }

    init(location: TrackedLocation, entryTime: Date, exitTime: Date, durationMinutes: Int) {
        self.id = UUID()
        self.location = location
        self.entryTime = entryTime
        self.exitTime = exitTime
        self.durationMinutes = durationMinutes
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let locationVisitCompleted = Notification.Name("locationVisitCompleted")
    static let geofenceEntered = Notification.Name("geofenceEntered")
    static let geofenceExited = Notification.Name("geofenceExited")
    static let locationAuthorizationChanged = Notification.Name("locationAuthorizationChanged")
}

// MARK: - Location Quest Definitions

extension LocationManager {

    /// Create default location-tracked quests
    static func createDefaultLocationQuests() -> [DailyQuest] {
        [
            DailyQuest(
                title: "Gym Rat",
                description: "Spend 45+ minutes at the gym.",
                difficulty: .hard,
                targetStats: [.strength, .vitality],
                trackingType: .location,
                targetValue: 45,
                unit: "minutes",
                locationCoordinate: nil // Set by user
            ),
            DailyQuest(
                title: "Scholar's Haven",
                description: "Study at the library for 60+ minutes.",
                difficulty: .hard,
                targetStats: [.intelligence],
                trackingType: .location,
                targetValue: 60,
                unit: "minutes",
                locationCoordinate: nil // Set by user
            ),
            DailyQuest(
                title: "Touch Grass",
                description: "Spend time outdoors in a park.",
                difficulty: .easy,
                targetStats: [.vitality, .spirit],
                trackingType: .location,
                targetValue: 20,
                unit: "minutes",
                locationCoordinate: nil // Set by user
            )
        ]
    }
}
