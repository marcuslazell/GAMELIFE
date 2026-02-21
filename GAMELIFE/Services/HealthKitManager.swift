//
//  HealthKitManager.swift
//  GAMELIFE
//
//  [SYSTEM]: Body metrics scanner initialized.
//  Your physical vessel is now monitored.
//

import Foundation
import HealthKit
import Combine

// MARK: - HealthKit Manager

/// Manages all HealthKit interactions for automatic quest tracking
/// Tracks: Steps, Sleep, Workouts, Active Energy, Stand Hours
@MainActor
class HealthKitManager: ObservableObject {

    static let shared = HealthKitManager()

    private let healthStore = HKHealthStore()
    private var observers: [HKObserverQuery] = []

    // MARK: - Published Properties

    @Published var isAuthorized = false
    @Published var authorizationStatus: HKAuthorizationStatus = .notDetermined
    @Published var lastSyncDate: Date?
    @Published var lastDetectedEvent: String = "No Health events detected yet."
    @Published var backgroundDeliveryEnabled = false

    // Today's metrics
    @Published var todaySteps: Int = 0
    @Published var todaySleepHours: Double = 0
    @Published var todayActiveEnergy: Double = 0 // kcal
    @Published var todayWorkoutMinutes: Int = 0
    @Published var todayWorkoutCount: Int = 0
    @Published var todayStandHours: Int = 0
    @Published var todayMindfulMinutes: Int = 0
    @Published var todayDistanceKM: Double = 0
    @Published var todayWaterGlasses: Double = 0
    @Published var currentBodyWeightLB: Double = 0
    @Published var currentBodyFatPercent: Double = 0

    // MARK: - Health Types

    /// Types we want to read from HealthKit
    private let readTypes: Set<HKObjectType> = [
        HKQuantityType(.stepCount),
        HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.appleStandTime),
        HKQuantityType(.appleExerciseTime),
        HKQuantityType(.dietaryWater),
        HKQuantityType(.bodyMass),
        HKQuantityType(.bodyFatPercentage),
        HKCategoryType(.appleStandHour),
        HKCategoryType(.sleepAnalysis),
        HKCategoryType(.mindfulSession),
        HKWorkoutType.workoutType()
    ]

    // MARK: - Initialization

    private init() {
        Task {
            await refreshAuthorizationStatus()
        }
    }

    // MARK: - Authorization

    /// Check if HealthKit is available on this device
    var isHealthKitAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    /// Request authorization to read health data
    func requestAuthorization() async throws {
        guard isHealthKitAvailable else {
            throw HealthKitError.notAvailable
        }

        guard hasNonEmptyInfoPlistValue("NSHealthShareUsageDescription") else {
            throw HealthKitError.misconfigured("Missing NSHealthShareUsageDescription in Info.plist.")
        }

        try await healthStore.requestAuthorization(toShare: [], read: readTypes)

        await refreshAuthorizationStatus()

        if isAuthorized {
            setupObservers()
            fetchAllTodayData()
        }
    }

    /// Re-evaluate HealthKit read authorization using lightweight probes.
    func refreshAuthorizationStatus() async {
        guard isHealthKitAvailable else { return }

        let statuses = readTypes.map { healthStore.authorizationStatus(for: $0) }
        let hasReadAccess = await detectReadableHealthType()

        if hasReadAccess || statuses.contains(.sharingAuthorized) {
            authorizationStatus = .sharingAuthorized
            isAuthorized = true
        } else if statuses.contains(.sharingDenied) {
            authorizationStatus = .sharingDenied
            isAuthorized = false
        } else {
            authorizationStatus = .notDetermined
            isAuthorized = false
        }
    }

    /// Because `authorizationStatus(for:)` reflects sharing, probe read access directly.
    private func detectReadableHealthType() async -> Bool {
        let probes: [HKSampleType] = [
            HKQuantityType(.stepCount),
            HKWorkoutType.workoutType(),
            HKCategoryType(.sleepAnalysis)
        ]

        for type in probes {
            if await canRead(sampleType: type) {
                return true
            }
        }
        return false
    }

    private func canRead(sampleType: HKSampleType) async -> Bool {
        await withCheckedContinuation { continuation in
            let start = Calendar.current.date(byAdding: .day, value: -14, to: Date())
            let predicate = HKQuery.predicateForSamples(
                withStart: start,
                end: Date(),
                options: .strictStartDate
            )

            let query = HKSampleQuery(
                sampleType: sampleType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, _, error in
                if let hkError = error as? HKError {
                    if hkError.code == .errorAuthorizationDenied {
                        continuation.resume(returning: false)
                        return
                    }
                    continuation.resume(returning: false)
                    return
                }
                continuation.resume(returning: error == nil)
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Data Fetching

    /// Fetch all relevant data for today
    func fetchAllTodayData() {
        Task {
            await refreshTodayData()
        }
    }

    /// Deterministic refresh entry point used by pull-to-refresh and observers.
    func refreshTodayData() async {
        async let steps = fetchTodaySteps()
        async let sleep = fetchTodaySleep()
        async let energy = fetchTodayActiveEnergy()
        async let workouts = fetchTodayWorkoutMinutes()
        async let workoutCount = fetchTodayWorkoutCount()
        async let mindful = fetchTodayMindfulMinutes()
        async let distance = fetchTodayDistanceKM()
        async let water = fetchTodayWaterGlasses()
        async let standHours = fetchTodayStandHours()
        async let weight = fetchLatestBodyWeightLB()
        async let bodyFat = fetchLatestBodyFatPercent()

        let (
            stepsResult,
            sleepResult,
            energyResult,
            workoutsResult,
            workoutCountResult,
            mindfulResult,
            distanceResult,
            waterResult,
            standHoursResult,
            weightResult,
            bodyFatResult
        ) = await (
            steps,
            sleep,
            energy,
            workouts,
            workoutCount,
            mindful,
            distance,
            water,
            standHours,
            weight,
            bodyFat
        )

        todaySteps = stepsResult
        todaySleepHours = sleepResult
        todayActiveEnergy = energyResult
        todayWorkoutMinutes = workoutsResult
        todayWorkoutCount = workoutCountResult
        todayMindfulMinutes = mindfulResult
        todayDistanceKM = distanceResult
        todayWaterGlasses = waterResult
        todayStandHours = standHoursResult
        currentBodyWeightLB = weightResult
        currentBodyFatPercent = bodyFatResult
        recordSync(event: "Health metrics refreshed")

        NotificationCenter.default.post(name: .healthKitDataDidUpdate, object: nil)
    }

    // MARK: - Steps

    /// Fetch today's step count
    func fetchTodaySteps() async -> Int {
        let stepType = HKQuantityType(.stepCount)
        let predicate = createTodayPredicate()

        do {
            let statistics = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HKStatistics, Error>) in
                let query = HKStatisticsQuery(
                    quantityType: stepType,
                    quantitySamplePredicate: predicate,
                    options: .cumulativeSum
                ) { _, result, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let result = result {
                        continuation.resume(returning: result)
                    } else {
                        continuation.resume(throwing: HealthKitError.noData)
                    }
                }
                healthStore.execute(query)
            }

            let steps = statistics.sumQuantity()?.doubleValue(for: .count()) ?? 0
            return Int(steps)
        } catch {
            if isNoDataHealthKitError(error) {
                return 0
            }
            print("[SYSTEM] Failed to fetch steps: \(error)")
            return 0
        }
    }

    // MARK: - Sleep

    /// Fetch last night's sleep duration in hours
    func fetchTodaySleep() async -> Double {
        let sleepType = HKCategoryType(.sleepAnalysis)

        // Look at sleep from the last 24 hours
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: startOfDay)!

        let predicate = HKQuery.predicateForSamples(
            withStart: yesterday,
            end: now,
            options: .strictEndDate
        )

        do {
            let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKCategorySample], Error>) in
                let query = HKSampleQuery(
                    sampleType: sleepType,
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: nil
                ) { _, results, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        let samples = results as? [HKCategorySample] ?? []
                        continuation.resume(returning: samples)
                    }
                }
                healthStore.execute(query)
            }

            // Sum up asleep time (not in bed, actually asleep)
            var totalSleepSeconds: TimeInterval = 0
            for sample in samples {
                // Check for asleep states (not just in bed)
                let value = sample.value
                if value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                   value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                   value == HKCategoryValueSleepAnalysis.asleepREM.rawValue ||
                   value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue {
                    totalSleepSeconds += sample.endDate.timeIntervalSince(sample.startDate)
                }
            }

            return totalSleepSeconds / 3600.0 // Convert to hours
        } catch {
            if isNoDataHealthKitError(error) {
                return 0
            }
            print("[SYSTEM] Failed to fetch sleep: \(error)")
            return 0
        }
    }

    // MARK: - Active Energy

    /// Fetch today's active energy burned in kcal
    func fetchTodayActiveEnergy() async -> Double {
        let energyType = HKQuantityType(.activeEnergyBurned)
        let predicate = createTodayPredicate()

        do {
            let statistics = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HKStatistics, Error>) in
                let query = HKStatisticsQuery(
                    quantityType: energyType,
                    quantitySamplePredicate: predicate,
                    options: .cumulativeSum
                ) { _, result, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let result = result {
                        continuation.resume(returning: result)
                    } else {
                        continuation.resume(throwing: HealthKitError.noData)
                    }
                }
                healthStore.execute(query)
            }

            return statistics.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
        } catch {
            if isNoDataHealthKitError(error) {
                return 0
            }
            print("[SYSTEM] Failed to fetch active energy: \(error)")
            return 0
        }
    }

    /// Fetch today's distance walked/ran in kilometers
    func fetchTodayDistanceKM() async -> Double {
        let type = HKQuantityType(.distanceWalkingRunning)
        let predicate = createTodayPredicate()
        let meters = await fetchQuantitySum(for: type, unit: .meter(), predicate: predicate)
        return meters / 1000.0
    }

    /// Fetch today's water intake in 250ml "glasses"
    func fetchTodayWaterGlasses() async -> Double {
        let type = HKQuantityType(.dietaryWater)
        let predicate = createTodayPredicate()
        let liters = await fetchQuantitySum(for: type, unit: .liter(), predicate: predicate)
        return liters / 0.25
    }

    /// Fetch today's stand hours
    func fetchTodayStandHours() async -> Int {
        let standMinutesType = HKQuantityType(.appleStandTime)
        let predicate = createTodayPredicate()
        let minutes = await fetchQuantitySum(for: standMinutesType, unit: .minute(), predicate: predicate)
        return Int(minutes / 60.0)
    }

    // MARK: - Workouts

    /// Fetch today's total workout minutes
    func fetchTodayWorkoutMinutes() async -> Int {
        let predicate = createTodayPredicate()
        return await fetchWorkoutMinutes(predicate: predicate)
    }

    /// Fetch today's workout count.
    func fetchTodayWorkoutCount() async -> Int {
        let predicate = createTodayPredicate()
        return await fetchWorkoutCount(predicate: predicate)
    }

    /// Fetch workout count for an arbitrary window.
    func fetchWorkoutCount(from startDate: Date, to endDate: Date = Date()) async -> Int {
        let predicate = createPredicate(from: startDate, to: endDate)
        return await fetchWorkoutCount(predicate: predicate)
    }

    /// Fetch workout minutes for any predicate window.
    private func fetchWorkoutMinutes(predicate: NSPredicate) async -> Int {
        do {
            let workouts = try await fetchWorkouts(predicate: predicate)
            let totalSeconds = workouts.reduce(0) { $0 + $1.duration }
            return Int(totalSeconds / 60)
        } catch {
            if isNoDataHealthKitError(error) {
                return 0
            }
            print("[SYSTEM] Failed to fetch workout minutes: \(error)")
            return 0
        }
    }

    /// Fetch workout count for any predicate window.
    private func fetchWorkoutCount(predicate: NSPredicate) async -> Int {
        do {
            let workouts = try await fetchWorkouts(predicate: predicate)
            return workouts.count
        } catch {
            if isNoDataHealthKitError(error) {
                return 0
            }
            print("[SYSTEM] Failed to fetch workout count: \(error)")
            return 0
        }
    }

    private func fetchWorkouts(predicate: NSPredicate) async throws -> [HKWorkout] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKWorkout], Error>) in
            let query = HKSampleQuery(
                sampleType: HKWorkoutType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, results, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    let workouts = results as? [HKWorkout] ?? []
                    continuation.resume(returning: workouts)
                }
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Mindfulness

    /// Fetch today's mindfulness minutes
    func fetchTodayMindfulMinutes() async -> Int {
        let mindfulType = HKCategoryType(.mindfulSession)
        let predicate = createTodayPredicate()

        do {
            let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKCategorySample], Error>) in
                let query = HKSampleQuery(
                    sampleType: mindfulType,
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: nil
                ) { _, results, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        let samples = results as? [HKCategorySample] ?? []
                        continuation.resume(returning: samples)
                    }
                }
                healthStore.execute(query)
            }

            let totalSeconds = samples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
            return Int(totalSeconds / 60)
        } catch {
            if isNoDataHealthKitError(error) {
                return 0
            }
            print("[SYSTEM] Failed to fetch mindfulness: \(error)")
            return 0
        }
    }

    // MARK: - Location-Based (Gym Detection)

    /// Check if user was at a specific location for a minimum duration
    /// Note: This requires CoreLocation integration - see LocationManager
    func checkGymVisit(latitude: Double, longitude: Double, minimumMinutes: Int) async -> Bool {
        // This would integrate with CoreLocation geofencing
        // For now, return false - actual implementation in LocationManager
        return false
    }

    // MARK: - Background Observers

    /// Set up background observers for real-time updates
    private func setupObservers() {
        // Step count observer
        setupObserver(for: HKQuantityType(.stepCount)) { [weak self] in
            Task {
                let steps = await self?.fetchTodaySteps() ?? 0
                await MainActor.run {
                    self?.todaySteps = steps
                    self?.recordSync(event: "Steps updated")
                }
                NotificationCenter.default.post(name: .healthKitDataDidUpdate, object: nil)
            }
        }

        // Distance observer
        setupObserver(for: HKQuantityType(.distanceWalkingRunning)) { [weak self] in
            Task {
                let distance = await self?.fetchTodayDistanceKM() ?? 0
                await MainActor.run {
                    self?.todayDistanceKM = distance
                    self?.recordSync(event: "Distance updated")
                }
                NotificationCenter.default.post(name: .healthKitDataDidUpdate, object: nil)
            }
        }

        // Sleep observer
        setupObserver(for: HKCategoryType(.sleepAnalysis)) { [weak self] in
            Task {
                let sleep = await self?.fetchTodaySleep() ?? 0
                await MainActor.run {
                    self?.todaySleepHours = sleep
                    self?.recordSync(event: "Sleep updated")
                }
                NotificationCenter.default.post(name: .healthKitDataDidUpdate, object: nil)
            }
        }

        // Workout observer
        setupObserver(for: HKWorkoutType.workoutType()) { [weak self] in
            Task {
                let minutes = await self?.fetchTodayWorkoutMinutes() ?? 0
                let count = await self?.fetchTodayWorkoutCount() ?? 0
                await MainActor.run {
                    self?.todayWorkoutMinutes = minutes
                    self?.todayWorkoutCount = count
                    self?.recordSync(event: "Workout data updated")
                }
                NotificationCenter.default.post(name: .healthKitDataDidUpdate, object: nil)
            }
        }

        // Active energy observer
        setupObserver(for: HKQuantityType(.activeEnergyBurned)) { [weak self] in
            Task {
                let energy = await self?.fetchTodayActiveEnergy() ?? 0
                await MainActor.run {
                    self?.todayActiveEnergy = energy
                    self?.recordSync(event: "Active energy updated")
                }
                NotificationCenter.default.post(name: .healthKitDataDidUpdate, object: nil)
            }
        }

        // Stand time observer
        setupObserver(for: HKQuantityType(.appleStandTime)) { [weak self] in
            Task {
                let standHours = await self?.fetchTodayStandHours() ?? 0
                await MainActor.run {
                    self?.todayStandHours = standHours
                    self?.recordSync(event: "Stand hours updated")
                }
                NotificationCenter.default.post(name: .healthKitDataDidUpdate, object: nil)
            }
        }

        // Water observer
        setupObserver(for: HKQuantityType(.dietaryWater)) { [weak self] in
            Task {
                let glasses = await self?.fetchTodayWaterGlasses() ?? 0
                await MainActor.run {
                    self?.todayWaterGlasses = glasses
                    self?.recordSync(event: "Hydration updated")
                }
                NotificationCenter.default.post(name: .healthKitDataDidUpdate, object: nil)
            }
        }

        // Mindfulness observer
        setupObserver(for: HKCategoryType(.mindfulSession)) { [weak self] in
            Task {
                let mindfulMinutes = await self?.fetchTodayMindfulMinutes() ?? 0
                await MainActor.run {
                    self?.todayMindfulMinutes = mindfulMinutes
                    self?.recordSync(event: "Mindfulness updated")
                }
                NotificationCenter.default.post(name: .healthKitDataDidUpdate, object: nil)
            }
        }

        // Body mass observer
        setupObserver(for: HKQuantityType(.bodyMass)) { [weak self] in
            Task {
                let weight = await self?.fetchLatestBodyWeightLB() ?? 0
                await MainActor.run {
                    self?.currentBodyWeightLB = weight
                    self?.recordSync(event: "Body weight updated")
                }
                NotificationCenter.default.post(name: .healthKitDataDidUpdate, object: nil)
            }
        }

        // Body fat observer
        setupObserver(for: HKQuantityType(.bodyFatPercentage)) { [weak self] in
            Task {
                let bodyFat = await self?.fetchLatestBodyFatPercent() ?? 0
                await MainActor.run {
                    self?.currentBodyFatPercent = bodyFat
                    self?.recordSync(event: "Body fat updated")
                }
                NotificationCenter.default.post(name: .healthKitDataDidUpdate, object: nil)
            }
        }
    }

    /// Set up a single observer for a health type
    private func setupObserver(for type: HKSampleType, handler: @escaping () -> Void) {
        let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completionHandler, error in
            if error == nil {
                handler()
            }
            completionHandler()
        }

        healthStore.execute(query)
        observers.append(query)

        // Enable background delivery
        healthStore.enableBackgroundDelivery(for: type, frequency: .immediate) { success, error in
            Task { @MainActor [weak self] in
                if let error = error {
                    self?.backgroundDeliveryEnabled = false
                    print("[SYSTEM] Background delivery error for \(type): \(error)")
                } else if success {
                    self?.backgroundDeliveryEnabled = true
                }
            }
        }
    }

    private func recordSync(event: String) {
        lastSyncDate = Date()
        lastDetectedEvent = event
    }

    // MARK: - Quest Progress Checking

    /// Check progress for a specific health-based quest
    func checkQuestProgress(for quest: DailyQuest) async -> Double {
        guard quest.trackingType == .healthKit,
              let identifier = quest.healthKitIdentifier else {
            return 0
        }

        let predicate = createPredicate(for: quest)
        let targetValue = max(1, quest.targetValue)

        switch identifier {
        case "HKQuantityTypeIdentifierStepCount":
            let steps = await fetchQuantitySum(
                for: HKQuantityType(.stepCount),
                unit: .count(),
                predicate: predicate
            )
            return steps / targetValue

        case "HKQuantityTypeIdentifierDistanceWalkingRunning":
            let meters = await fetchQuantitySum(
                for: HKQuantityType(.distanceWalkingRunning),
                unit: .meter(),
                predicate: predicate
            )
            return (meters / 1000.0) / targetValue

        case "HKCategoryTypeIdentifierSleepAnalysis":
            let sleepHours = await fetchSleepHours(predicate: predicate)
            return sleepHours / targetValue

        case "HKQuantityTypeIdentifierActiveEnergyBurned":
            let energy = await fetchQuantitySum(
                for: HKQuantityType(.activeEnergyBurned),
                unit: .kilocalorie(),
                predicate: predicate
            )
            return energy / targetValue

        case "HKQuantityTypeIdentifierAppleExerciseTime":
            let minutes = await fetchQuantitySum(
                for: HKQuantityType(.appleExerciseTime),
                unit: .minute(),
                predicate: predicate
            )
            return minutes / targetValue

        case "HKWorkoutType":
            let workoutCount = await fetchWorkoutCount(predicate: predicate)
            return Double(workoutCount) / targetValue

        case "HKCategoryTypeIdentifierAppleStandHour":
            let standMinutes = await fetchQuantitySum(
                for: HKQuantityType(.appleStandTime),
                unit: .minute(),
                predicate: predicate
            )
            return (standMinutes / 60.0) / targetValue

        case "HKQuantityTypeIdentifierDietaryWater":
            let liters = await fetchQuantitySum(
                for: HKQuantityType(.dietaryWater),
                unit: .liter(),
                predicate: predicate
            )
            let glasses = liters / 0.25
            return glasses / targetValue

        case "HKCategoryTypeIdentifierMindfulSession":
            let minutes = await fetchCategoryDurationMinutes(
                for: HKCategoryType(.mindfulSession),
                predicate: predicate
            )
            return minutes / targetValue

        default:
            return 0
        }
    }

    // MARK: - Helpers

    private func fetchQuantitySum(
        for type: HKQuantityType,
        unit: HKUnit,
        predicate: NSPredicate
    ) async -> Double {
        do {
            let statistics = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HKStatistics, Error>) in
                let query = HKStatisticsQuery(
                    quantityType: type,
                    quantitySamplePredicate: predicate,
                    options: .cumulativeSum
                ) { _, result, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let result = result {
                        continuation.resume(returning: result)
                    } else {
                        continuation.resume(throwing: HealthKitError.noData)
                    }
                }
                healthStore.execute(query)
            }

            return statistics.sumQuantity()?.doubleValue(for: unit) ?? 0
        } catch {
            if isNoDataHealthKitError(error) {
                return 0
            }
            print("[SYSTEM] Failed to fetch quantity sum for \(type): \(error)")
            return 0
        }
    }

    private func isNoDataHealthKitError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == "com.apple.healthkit" && nsError.code == 11
    }

    private func fetchCategoryDurationMinutes(
        for type: HKCategoryType,
        predicate: NSPredicate
    ) async -> Double {
        do {
            let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKCategorySample], Error>) in
                let query = HKSampleQuery(
                    sampleType: type,
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: nil
                ) { _, results, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: results as? [HKCategorySample] ?? [])
                    }
                }
                healthStore.execute(query)
            }

            let seconds = samples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
            return seconds / 60.0
        } catch {
            if isNoDataHealthKitError(error) {
                return 0
            }
            print("[SYSTEM] Failed to fetch category duration for \(type): \(error)")
            return 0
        }
    }

    private func fetchSleepHours(predicate: NSPredicate) async -> Double {
        do {
            let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKCategorySample], Error>) in
                let query = HKSampleQuery(
                    sampleType: HKCategoryType(.sleepAnalysis),
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: nil
                ) { _, results, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: results as? [HKCategorySample] ?? [])
                    }
                }
                healthStore.execute(query)
            }

            let totalSleepSeconds = samples.reduce(0.0) { partial, sample in
                let value = sample.value
                let isSleepState = value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                    value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                    value == HKCategoryValueSleepAnalysis.asleepREM.rawValue ||
                    value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
                guard isSleepState else { return partial }
                return partial + sample.endDate.timeIntervalSince(sample.startDate)
            }

            return totalSleepSeconds / 3600.0
        } catch {
            if isNoDataHealthKitError(error) {
                return 0
            }
            print("[SYSTEM] Failed to fetch sleep hours: \(error)")
            return 0
        }
    }

    func fetchLatestBodyWeightLB() async -> Double {
        await fetchLatestQuantityValue(for: HKQuantityType(.bodyMass), unit: .pound())
    }

    func fetchLatestBodyFatPercent() async -> Double {
        let ratio = await fetchLatestQuantityValue(for: HKQuantityType(.bodyFatPercentage), unit: .percent())
        return ratio * 100.0
    }

    private func fetchLatestQuantityValue(for type: HKQuantityType, unit: HKUnit) async -> Double {
        await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, error in
                guard error == nil,
                      let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: 0)
                    return
                }
                continuation.resume(returning: sample.quantity.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }

    private func createPredicate(for quest: DailyQuest, now: Date = Date(), calendar: Calendar = .current) -> NSPredicate {
        let startDate = cycleStartDate(for: quest.resolvedFrequency, now: now, calendar: calendar)
        return createPredicate(from: startDate, to: now)
    }

    private func cycleStartDate(for frequency: QuestFrequency, now: Date, calendar: Calendar) -> Date {
        switch frequency {
        case .hourly:
            return calendar.dateInterval(of: .hour, for: now)?.start ?? now.addingTimeInterval(-3600)
        case .daily:
            return calendar.startOfDay(for: now)
        case .semiWeekly:
            let dayStart = calendar.startOfDay(for: now)
            return calendar.date(byAdding: .day, value: -3, to: dayStart) ?? dayStart
        case .weekly:
            return calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? calendar.startOfDay(for: now)
        case .monthly:
            return calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? calendar.startOfDay(for: now)
        }
    }

    /// Create a predicate for today's data
    private func createTodayPredicate() -> NSPredicate {
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)

        return createPredicate(from: startOfDay, to: now)
    }

    private func createPredicate(from startDate: Date, to endDate: Date) -> NSPredicate {
        HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictEndDate
        )
    }

    /// Clean up observers
    func cleanup() {
        for observer in observers {
            healthStore.stop(observer)
        }
        observers.removeAll()
    }

    private func hasNonEmptyInfoPlistValue(_ key: String) -> Bool {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return false
        }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - HealthKit Errors

enum HealthKitError: LocalizedError {
    case notAvailable
    case notAuthorized
    case noData
    case queryFailed(Error)
    case misconfigured(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "HealthKit is not available on this device."
        case .notAuthorized:
            return "HealthKit access has not been authorized."
        case .noData:
            return "No health data available."
        case .queryFailed(let error):
            return "Health query failed: \(error.localizedDescription)"
        case .misconfigured(let message):
            return message
        }
    }
}

// MARK: - HealthKit Quest Integration

extension HealthKitManager {

    /// Get auto-tracking quests that should be updated
    func getHealthKitQuests(from quests: [DailyQuest]) -> [DailyQuest] {
        quests.filter { $0.trackingType == .healthKit }
    }

    /// Update all HealthKit-tracked quests with current progress
    func updateQuestProgress(_ quests: inout [DailyQuest]) async {
        for i in quests.indices {
            if quests[i].trackingType == .healthKit {
                let progress = await checkQuestProgress(for: quests[i])
                quests[i].currentProgress = min(progress, 1.0)

                // Auto-complete if progress >= 100%
                if progress >= 1.0 && quests[i].status != .completed {
                    quests[i].status = .completed
                }
            }
        }
    }

    /// Create STR stat XP based on physical activity
    func calculateStrengthXP() async -> Int {
        let steps = await fetchTodaySteps()
        let workoutMinutes = await fetchTodayWorkoutMinutes()

        // XP formula: 1 XP per 1000 steps + 2 XP per workout minute
        let stepXP = steps / 1000
        let workoutXP = workoutMinutes * 2

        return stepXP + workoutXP
    }

    /// Create VIT stat XP based on vitality metrics
    func calculateVitalityXP() async -> Int {
        let sleepHours = await fetchTodaySleep()

        // XP formula: 10 XP for 7+ hours, 15 XP for 8+ hours
        if sleepHours >= 8 {
            return 15
        } else if sleepHours >= 7 {
            return 10
        } else if sleepHours >= 6 {
            return 5
        }
        return 0
    }

    /// Create SPI stat XP based on mindfulness
    func calculateSpiritXP() async -> Int {
        let mindfulMinutes = await fetchTodayMindfulMinutes()

        // XP formula: 5 XP per 5 minutes of mindfulness
        return (mindfulMinutes / 5) * 5
    }
}

extension Notification.Name {
    static let healthKitDataDidUpdate = Notification.Name("healthKitDataDidUpdate")
}
