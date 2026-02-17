//
//  QuestFormSheet.swift
//  GAMELIFE
//
//  Quest creation and editing.
//

import SwiftUI
import FamilyControls
import CoreLocation
import MapKit
import Combine

// MARK: - Quest Form Mode

enum QuestFormMode: Identifiable {
    case add
    case edit(DailyQuest)

    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let quest): return quest.id.uuidString
        }
    }

    var isEditing: Bool {
        if case .edit = self { return true }
        return false
    }

    var existingQuest: DailyQuest? {
        if case .edit(let quest) = self { return quest }
        return nil
    }
}

// MARK: - Quest Form Sheet

struct QuestFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var gameEngine: GameEngine

    let mode: QuestFormMode

    // Core form state
    @State private var title = ""
    @State private var description = ""
    @State private var difficulty: QuestDifficulty = .easy
    @State private var selectedStats: Set<StatType> = []
    @State private var trackingType: QuestTrackingType = .manual
    @State private var frequency: QuestFrequency = .daily
    @State private var targetValue: Double = 1
    @State private var unit = "times"

    // Tracking-specific state
    @State private var showScreenTimePicker = false
    @State private var screenTimeSelection = FamilyActivitySelection()
    @State private var healthKitType: HealthKitQuestType = .steps
    @State private var locationAddress = ""
    @State private var locationCoordinate: LocationCoordinate?
    @State private var locationRadiusMeters: Double = 804.67
    @State private var isValidatingAddress = false
    @State private var locationValidationMessage: String?
    @State private var locationValidationIsError = false
    @StateObject private var addressAutocomplete = AddressAutocompleteProvider()

    // Boss linking
    @State private var selectedBossID: UUID?
    @State private var showCreateBossSheet = false

    // Reminders
    @State private var reminderEnabled = false
    @State private var reminderTime = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var isOptionalQuest = false

    // UI state
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var linkableBosses: [BossFight] {
        gameEngine.activeBossFights.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private var selectedBoss: BossFight? {
        guard let selectedBossID else { return nil }
        return gameEngine.activeBossFights.first(where: { $0.id == selectedBossID })
    }

    private var estimatedBossDamage: Int {
        let baseDamage = GameFormulas.bossDamage(taskDifficulty: difficulty, playerLevel: gameEngine.player.level)
        return max(1, Int(Double(baseDamage) * 0.8))
    }

    private var estimatedBossDamagePercentage: Int {
        guard let selectedBoss, selectedBoss.maxHP > 0 else { return 0 }
        let ratio = (Double(estimatedBossDamage) / Double(selectedBoss.maxHP)) * 100
        return Int(max(0, min(100, ratio.rounded())))
    }

    private var isValid: Bool {
        let hasTitle = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasStats = !selectedStats.isEmpty
        let hasLocationAddress = trackingType != .location || !locationAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasScreenTimeSelection = trackingType != .screenTime || !AppFeatureFlags.screenTimeEnabled || (screenTimeSelection.applicationTokens.isEmpty == false || screenTimeSelection.categoryTokens.isEmpty == false)
        let hasValidatedLocation = trackingType != .location || locationCoordinate != nil
        return hasTitle && hasStats && hasLocationAddress && hasScreenTimeSelection && hasValidatedLocation
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Quest Title", text: $title)
                    TextField("Description (optional)", text: $description)
                } header: {
                    Text("Quest Details")
                }

                Section {
                    Picker("Difficulty", selection: $difficulty) {
                        ForEach(QuestDifficulty.allCases, id: \.self) { diff in
                            Label(diff.rawValue, systemImage: diff.icon)
                                .foregroundStyle(diff.color)
                                .tag(diff)
                        }
                    }
                    .pickerStyle(.menu)

                    HStack {
                        let previewXP = GameFormulas.questXP(difficulty: difficulty)
                        let previewGold = isOptionalQuest ? 0 : GameFormulas.questGold(difficulty: difficulty)
                        Text("Rewards")
                            .foregroundStyle(SystemTheme.textSecondary)
                        Spacer()
                        Label("+\(previewXP)", systemImage: "star.fill")
                            .foregroundStyle(SystemTheme.primaryBlue)
                        if previewGold > 0 {
                            Label("+\(previewGold)", systemImage: "dollarsign.circle.fill")
                                .foregroundStyle(SystemTheme.goldColor)
                        } else {
                            Text("XP only")
                                .foregroundStyle(SystemTheme.textTertiary)
                        }
                    }
                    .font(SystemTypography.mono(12, weight: .bold))

                    Toggle("Optional Quest (XP only)", isOn: $isOptionalQuest)
                } header: {
                    Text("Difficulty")
                } footer: {
                    Text("Optional quests never deal missed-quest HP damage. Completing them awards XP and stats, but no Gold.")
                }

                Section {
                    ForEach(StatType.allCases) { stat in
                        Button {
                            toggleStat(stat)
                        } label: {
                            HStack {
                                Image(systemName: stat.icon)
                                    .foregroundStyle(stat.color)
                                    .frame(width: 24)
                                Text(stat.fullName)
                                    .foregroundStyle(SystemTheme.textPrimary)
                                Text(stat.rawValue)
                                    .font(SystemTypography.mono(12, weight: .semibold))
                                    .foregroundStyle(stat.color)
                                Spacer()
                                if selectedStats.contains(stat) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(SystemTheme.primaryBlue)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Target Stats (Select 1-3)")
                } footer: {
                    Text("Selected stats receive XP when this quest is completed.")
                }

                Section {
                    Picker("Tracking Method", selection: $trackingType) {
                        ForEach(QuestTrackingType.betaSelectableTypes, id: \.self) { type in
                            Text(trackingLabel(for: type)).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    trackingConfigurationSection
                } header: {
                    Text("Tracking")
                } footer: {
                    trackingFooter
                }

                Section {
                    if linkableBosses.isEmpty {
                        Text("No active bosses yet.")
                            .foregroundStyle(SystemTheme.textTertiary)

                        Button {
                            showCreateBossSheet = true
                        } label: {
                            Label("Create Boss", systemImage: "plus.circle.fill")
                                .foregroundStyle(SystemTheme.primaryBlue)
                        }
                    } else {
                        Picker("Linked Boss", selection: $selectedBossID) {
                            Text("None").tag(UUID?.none)
                            ForEach(linkableBosses) { boss in
                                Text(boss.title).tag(Optional(boss.id))
                            }
                        }
                    }
                } header: {
                    Text("Boss Link")
                } footer: {
                    if let selectedBoss {
                        Text("Estimated impact: \(estimatedBossDamage) HP (~\(estimatedBossDamagePercentage)% of \(selectedBoss.title)'s max HP) each completion.")
                    } else {
                        Text("Completing this quest will damage the linked boss.")
                    }
                }

                Section {
                    Picker("Repeat", selection: $frequency) {
                        ForEach(QuestFrequency.allCases) { option in
                            Label(option.rawValue, systemImage: option.icon)
                                .tag(option)
                        }
                    }

                    Toggle("Enable Reminder", isOn: $reminderEnabled)

                    if reminderEnabled {
                        DatePicker(
                            "Reminder Time",
                            selection: $reminderTime,
                            displayedComponents: .hourAndMinute
                        )
                    }
                } header: {
                    Text("Schedule")
                } footer: {
                    Text("Set how often the quest resets and optionally schedule a reminder.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(SystemTheme.backgroundPrimary)
            .navigationTitle(mode.isEditing ? "Edit Quest" : "Create Quest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.isEditing ? "Save" : "Create") {
                        Task { await saveQuest() }
                    }
                    .disabled(!isValid || isSaving)
                }
            }
            .sheet(isPresented: $showScreenTimePicker) {
                ScreenTimeLinkSheet(selection: $screenTimeSelection)
            }
            .sheet(isPresented: $showCreateBossSheet) {
                BossFormSheet()
            }
            .alert("Unable to Save Quest", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
            .onAppear(perform: loadExistingQuest)
            .onChange(of: trackingType) { _, newType in
                if !AppFeatureFlags.screenTimeEnabled && newType == .screenTime {
                    trackingType = .manual
                    return
                }
                if newType == .location && targetValue < 5 {
                    targetValue = 45
                }
                if newType != .location {
                    locationValidationMessage = nil
                    locationValidationIsError = false
                    addressAutocomplete.clear()
                }
            }
            .onChange(of: locationRadiusMeters) { _, newValue in
                guard let existing = locationCoordinate else { return }
                locationCoordinate = LocationCoordinate(
                    latitude: existing.latitude,
                    longitude: existing.longitude,
                    radius: newValue,
                    locationName: existing.locationName
                )
            }
            .onChange(of: locationAddress) { _, _ in
                guard trackingType == .location else { return }
                locationCoordinate = nil
                locationValidationMessage = nil
                locationValidationIsError = false
                addressAutocomplete.updateQuery(locationAddress)
            }
        }
    }

    @ViewBuilder
    private var trackingConfigurationSection: some View {
        switch trackingType {
        case .manual:
            VStack(alignment: .leading, spacing: 8) {
                Text("Target Value")
                    .font(SystemTypography.caption)
                    .foregroundStyle(SystemTheme.textSecondary)

                HStack {
                    Stepper(value: $targetValue, in: 1...1000, step: 1) {
                        Text("\(Int(targetValue))")
                            .font(SystemTypography.mono(16, weight: .bold))
                    }

                    TextField("unit", text: $unit)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
            }

        case .healthKit:
            Picker("Data Type", selection: $healthKitType) {
                ForEach(HealthKitQuestType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }

            HStack {
                Text("Target")
                    .foregroundStyle(SystemTheme.textSecondary)
                TextField("", value: $targetValue, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .frame(width: 100)
                Text(healthKitType.unit)
                    .foregroundStyle(SystemTheme.textSecondary)
            }

        case .screenTime:
            if !AppFeatureFlags.screenTimeEnabled {
                Text("Usage tracking is temporarily disabled for this beta.")
                    .font(SystemTypography.caption)
                    .foregroundStyle(SystemTheme.textTertiary)
            } else {
                Button {
                    showScreenTimePicker = true
                } label: {
                    HStack {
                        Image(systemName: "apps.iphone")
                            .foregroundStyle(SystemTheme.primaryBlue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Select Apps/Categories")
                                .foregroundStyle(SystemTheme.textPrimary)
                            let selectedCount = screenTimeSelection.applicationTokens.count + screenTimeSelection.categoryTokens.count
                            Text(selectedCount == 0 ? "No selections yet" : "\(selectedCount) selection(s) linked")
                                .font(SystemTypography.captionSmall)
                                .foregroundStyle(selectedCount == 0 ? SystemTheme.textTertiary : SystemTheme.primaryBlue)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundStyle(SystemTheme.textTertiary)
                    }
                }

                HStack {
                    Text("Target duration")
                        .foregroundStyle(SystemTheme.textSecondary)
                    TextField("", value: $targetValue, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .frame(width: 100)
                    Text("minutes")
                        .foregroundStyle(SystemTheme.textSecondary)
                }
            }

        case .location:
            TextField("Address (e.g. 1 Infinite Loop, Cupertino)", text: $locationAddress)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()

            if addressAutocomplete.isSearching {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(SystemTheme.primaryBlue)
                    Text("Searching Apple Maps…")
                        .font(SystemTypography.captionSmall)
                        .foregroundStyle(SystemTheme.textSecondary)
                }
            }

            if !addressAutocomplete.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(addressAutocomplete.suggestions) { suggestion in
                        Button {
                            Task { await selectAddressSuggestion(suggestion) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.primaryText)
                                    .font(SystemTypography.bodySmall)
                                    .foregroundStyle(SystemTheme.textPrimary)
                                if let secondary = suggestion.secondaryText, !secondary.isEmpty {
                                    Text(secondary)
                                        .font(SystemTypography.captionSmall)
                                        .foregroundStyle(SystemTheme.textTertiary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                        }
                        if suggestion.id != addressAutocomplete.suggestions.last?.id {
                            Divider()
                                .overlay(SystemTheme.borderPrimary)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .background(SystemTheme.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: SystemRadius.small))
            }

            Button {
                Task { await validateLocationAddress() }
            } label: {
                HStack {
                    if isValidatingAddress {
                        ProgressView()
                            .tint(SystemTheme.primaryBlue)
                    } else {
                        Image(systemName: "map.fill")
                            .foregroundStyle(SystemTheme.primaryBlue)
                    }
                    Text(isValidatingAddress ? "Validating with Apple Maps..." : "Validate Address (Apple Maps)")
                        .foregroundStyle(SystemTheme.textPrimary)
                    Spacer()
                }
            }
            .disabled(isValidatingAddress || locationAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            HStack {
                Text("Minimum stay")
                    .foregroundStyle(SystemTheme.textSecondary)
                Stepper(value: $targetValue, in: 5...240, step: 5) {
                    Text("\(Int(targetValue)) minutes")
                        .font(SystemTypography.mono(14, weight: .semibold))
                }
            }

            HStack {
                Text("Tracking radius")
                    .foregroundStyle(SystemTheme.textSecondary)
                Stepper(value: $locationRadiusMeters, in: 100...1609, step: 50) {
                    Text("\(radiusLabel)")
                        .font(SystemTypography.mono(14, weight: .semibold))
                }
            }

            if let locationCoordinate {
                let previewPoint = QuestLocationPreviewPoint(
                    coordinate: CLLocationCoordinate2D(latitude: locationCoordinate.latitude, longitude: locationCoordinate.longitude),
                    title: locationCoordinate.locationName
                )
                let previewRegion = MKCoordinateRegion(
                    center: previewPoint.coordinate,
                    latitudinalMeters: max(400, locationRadiusMeters * 2.5),
                    longitudinalMeters: max(400, locationRadiusMeters * 2.5)
                )

                Map(initialPosition: .region(previewRegion)) {
                    Annotation("Target", coordinate: previewPoint.coordinate) {
                        VStack(spacing: 4) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(SystemTheme.primaryBlue)
                            Text("Target")
                                .font(SystemTypography.captionSmall)
                                .foregroundStyle(SystemTheme.textSecondary)
                        }
                    }
                }
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: SystemRadius.small))
                .overlay(
                    RoundedRectangle(cornerRadius: SystemRadius.small)
                        .stroke(SystemTheme.borderSecondary, lineWidth: 1)
                )

                Button {
                    openValidatedLocationInMaps(locationCoordinate)
                } label: {
                    Label("Open in Maps", systemImage: "map")
                        .font(SystemTypography.caption)
                }
            }

            HStack(alignment: .top) {
                Image(systemName: "location.circle.fill")
                    .foregroundStyle(SystemTheme.statAgility)
                Text("Quest auto-completes after you stay within \(radiusLabel) for the minimum time.")
                    .font(SystemTypography.captionSmall)
                    .foregroundStyle(SystemTheme.textSecondary)
            }

            if let locationCoordinate {
                Text("Saved: \(locationCoordinate.locationName)")
                    .font(SystemTypography.captionSmall)
                    .foregroundStyle(SystemTheme.successGreen)

                Text("Tracking armed after save. The app confirms live status on the quest card.")
                    .font(SystemTypography.captionSmall)
                    .foregroundStyle(SystemTheme.textSecondary)
            }

            if let locationValidationMessage {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: locationValidationIsError ? "xmark.octagon.fill" : "checkmark.seal.fill")
                        .foregroundStyle(locationValidationIsError ? SystemTheme.criticalRed : SystemTheme.successGreen)
                    Text(locationValidationMessage)
                        .font(SystemTypography.captionSmall)
                        .foregroundStyle(locationValidationIsError ? SystemTheme.criticalRed : SystemTheme.successGreen)
                }
            }

        case .timer:
            EmptyView()
        }
    }

    @ViewBuilder
    private var trackingFooter: some View {
        switch trackingType {
        case .manual:
            Text("You manually mark this quest complete.")
        case .healthKit:
            if healthKitType == .workoutCount {
                Text("Auto-completes when Apple Health records workouts from Fitness/Activity, Apple Watch, or synced apps like Strava/Peloton.")
            } else {
                Text("Progress auto-tracked with Apple Health (including data synced from Fitness, Strava, Peloton, and more).")
            }
        case .screenTime:
            if AppFeatureFlags.screenTimeEnabled {
                Text("Progress auto-tracked with Screen Time APIs.")
            } else {
                Text("Usage tracking is temporarily disabled in this beta.")
            }
        case .location:
            Text("Validate with Apple Maps first. Quest auto-completes after staying within the configured radius (\(radiusLabel)) for the configured duration.")
        case .timer:
            EmptyView()
        }
    }

    private func toggleStat(_ stat: StatType) {
        if selectedStats.contains(stat) {
            selectedStats.remove(stat)
        } else if selectedStats.count < 3 {
            selectedStats.insert(stat)
        }
    }

    private func loadExistingQuest() {
        guard let quest = mode.existingQuest else { return }

        title = quest.title
        description = quest.description
        difficulty = quest.difficulty
        selectedStats = Set(quest.targetStats)
        trackingType = quest.trackingType
        if !AppFeatureFlags.screenTimeEnabled && trackingType == .screenTime {
            trackingType = .manual
        }
        frequency = quest.resolvedFrequency
        targetValue = quest.targetValue
        unit = quest.unit
        reminderEnabled = quest.reminderEnabled
        reminderTime = quest.reminderTime ?? reminderTime
        isOptionalQuest = quest.isOptional
        locationAddress = quest.locationAddress ?? ""
        locationCoordinate = quest.locationCoordinate
        locationRadiusMeters = quest.locationCoordinate?.radius ?? 804.67
        if let savedCoordinate = quest.locationCoordinate {
            locationValidationMessage = "Address validated: \(savedCoordinate.locationName)"
            locationValidationIsError = false
        }

        if AppFeatureFlags.screenTimeEnabled,
           quest.trackingType == .screenTime,
           let selectionData = quest.screenTimeSelectionData,
           let selection = ScreenTimeManager.shared.decodeSelection(from: selectionData) {
            screenTimeSelection = selection
        }

        if quest.trackingType == .location, quest.unit == "visits", quest.targetValue <= 1 {
            targetValue = 45
        }

        if let explicitBossID = quest.linkedBossID {
            selectedBossID = explicitBossID
        } else {
            selectedBossID = gameEngine.activeBossFights.first(where: { $0.linkedQuestIDs.contains(quest.id) })?.id
        }

        if let hkIdentifier = quest.healthKitIdentifier {
            healthKitType = HealthKitQuestType.allCases.first { $0.identifier == hkIdentifier } ?? .steps
        }
    }

    private func saveQuest() async {
        guard isValid else { return }
        isSaving = true
        defer { isSaving = false }

        let existingQuest = mode.existingQuest
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAddress = locationAddress.trimmingCharacters(in: .whitespacesAndNewlines)

        let resolvedCoordinate: LocationCoordinate?
        if trackingType == .location {
            if trimmedAddress.isEmpty {
                errorMessage = "Please enter an address for location tracking."
                return
            }

            let baseCoordinate: LocationCoordinate?
            if existingQuest?.locationAddress == trimmedAddress, let existingCoordinate = existingQuest?.locationCoordinate {
                baseCoordinate = existingCoordinate
            } else if let validatedCoordinate = locationCoordinate {
                baseCoordinate = validatedCoordinate
            } else if let resolved = await resolveAddressWithAppleMaps(trimmedAddress) {
                baseCoordinate = resolved
            } else {
                errorMessage = "Could not validate that address with Apple Maps. Try a fuller street + city + state address."
                return
            }

            guard let baseCoordinate else {
                errorMessage = "Could not resolve that address."
                return
            }

            resolvedCoordinate = LocationCoordinate(
                latitude: baseCoordinate.latitude,
                longitude: baseCoordinate.longitude,
                radius: locationRadiusMeters,
                locationName: baseCoordinate.locationName
            )
        } else {
            resolvedCoordinate = nil
        }

        let now = Date()
        let questID = existingQuest?.id ?? UUID()
        let resolvedTrackingType: QuestTrackingType =
            (!AppFeatureFlags.screenTimeEnabled && trackingType == .screenTime) ? .manual : trackingType
        let previousFrequency = existingQuest?.resolvedFrequency
        let expiresAt: Date
        if let existingQuest, previousFrequency == frequency {
            expiresAt = existingQuest.expiresAt
        } else {
            expiresAt = frequency.nextResetDate(from: now)
        }

        if resolvedTrackingType == .screenTime {
            ScreenTimeManager.shared.selectedAppsToTrack = screenTimeSelection
        }

        let newQuest = DailyQuest(
            id: questID,
            title: trimmedTitle,
            description: trimmedDescription.isEmpty ? defaultDescription(for: resolvedTrackingType, address: trimmedAddress) : trimmedDescription,
            difficulty: difficulty,
            status: existingQuest?.status ?? .available,
            targetStats: Array(selectedStats),
            frequency: frequency,
            isOptional: isOptionalQuest,
            trackingType: resolvedTrackingType,
            currentProgress: existingQuest?.currentProgress ?? 0,
            targetValue: max(1, targetValue),
            unit: effectiveUnit,
            createdAt: existingQuest?.createdAt ?? now,
            expiresAt: expiresAt,
            healthKitIdentifier: resolvedTrackingType == .healthKit ? healthKitType.identifier : nil,
            screenTimeCategory: resolvedTrackingType == .screenTime ? ScreenTimeManager.shared.getSelectionSummary(screenTimeSelection) : nil,
            screenTimeSelectionData: resolvedTrackingType == .screenTime ? ScreenTimeManager.shared.encodeSelection(screenTimeSelection) : nil,
            locationCoordinate: resolvedCoordinate,
            locationAddress: resolvedTrackingType == .location ? trimmedAddress : nil,
            linkedBossID: selectedBossID,
            reminderEnabled: reminderEnabled,
            reminderTime: reminderEnabled ? reminderTime : nil
        )

        gameEngine.saveQuest(newQuest, replacing: existingQuest?.id)
        dismiss()
    }

    private func validateLocationAddress() async {
        let trimmed = locationAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            locationCoordinate = nil
            locationValidationMessage = "Enter an address before validating."
            locationValidationIsError = true
            return
        }

        isValidatingAddress = true
        defer { isValidatingAddress = false }

        if let resolved = await resolveAddressWithAppleMaps(trimmed) {
            locationCoordinate = LocationCoordinate(
                latitude: resolved.latitude,
                longitude: resolved.longitude,
                radius: locationRadiusMeters,
                locationName: resolved.locationName
            )
            locationValidationMessage = "Validated: \(resolved.locationName)"
            locationValidationIsError = false
            addressAutocomplete.clear()
        } else {
            locationCoordinate = nil
            locationValidationMessage = "Address not found. Try a complete address (street, city, state)."
            locationValidationIsError = true
        }
    }

    private func selectAddressSuggestion(_ suggestion: AddressSuggestion) async {
        locationAddress = suggestion.fullText
        await validateLocationAddress()
    }

    private func resolveAddressWithAppleMaps(_ address: String) async -> LocationCoordinate? {
        if let mapResult = await searchAddressWithMapKit(address) {
            return mapResult
        }
        // Fallback to geocoder for compatibility on sparse map results.
        return await geocodeAddress(address)
    }

    private func searchAddressWithMapKit(_ address: String) async -> LocationCoordinate? {
        await withCheckedContinuation { continuation in
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = address
            request.resultTypes = .address

            let search = MKLocalSearch(request: request)
            search.start { response, _ in
                guard let item = response?.mapItems.first else {
                    continuation.resume(returning: nil)
                    return
                }

                let coordinate = item.placemark.coordinate
                guard CLLocationCoordinate2DIsValid(coordinate) else {
                    continuation.resume(returning: nil)
                    return
                }

                let resolvedName = [
                    item.name,
                    item.placemark.title
                ]
                .compactMap { $0 }
                .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? address

                continuation.resume(returning: LocationCoordinate(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    radius: 804.67, // ~0.5 miles
                    locationName: resolvedName
                ))
            }
        }
    }

    private func geocodeAddress(_ address: String) async -> LocationCoordinate? {
        await withCheckedContinuation { continuation in
            CLGeocoder().geocodeAddressString(address) { placemarks, _ in
                guard let placemark = placemarks?.first,
                      let coordinate = placemark.location?.coordinate else {
                    continuation.resume(returning: nil)
                    return
                }

                let resolvedName = [
                    placemark.name,
                    placemark.locality,
                    placemark.administrativeArea
                ]
                .compactMap { $0 }
                .joined(separator: ", ")

                continuation.resume(returning: LocationCoordinate(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    radius: 804.67, // ~0.5 miles
                    locationName: resolvedName.isEmpty ? address : resolvedName
                ))
            }
        }
    }

    private func defaultDescription(for trackingType: QuestTrackingType, address: String) -> String {
        switch trackingType {
        case .manual: return "Complete this task to grow stronger."
        case .healthKit: return "Tracked via Apple Health."
        case .screenTime: return "Tracked via Screen Time."
        case .location:
            let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
            let minimumMinutes = Int(max(5, targetValue))
            return trimmedAddress.isEmpty
                ? "Stay near this location for \(minimumMinutes) minutes to complete."
                : "Auto-completes when you stay near \(trimmedAddress) for \(minimumMinutes) minutes."
        case .timer: return "Complete a focused session."
        }
    }

    private var effectiveUnit: String {
        switch trackingType {
        case .healthKit:
            return healthKitType.unit
        case .screenTime:
            return "minutes"
        case .location:
            return "minutes"
        default:
            return unit
        }
    }

    private func trackingLabel(for type: QuestTrackingType) -> String {
        switch type {
        case .manual: return "Manual"
        case .healthKit: return "Health"
        case .screenTime: return "Usage"
        case .location: return "Location"
        case .timer: return "Timer"
        }
    }

    private var radiusLabel: String {
        let miles = locationRadiusMeters / 1609.34
        return String(format: "%.2f mi (%.0f m)", miles, locationRadiusMeters)
    }

    private func openValidatedLocationInMaps(_ coordinate: LocationCoordinate) {
        let placemark = MKPlacemark(
            coordinate: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
        )
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = coordinate.locationName
        mapItem.openInMaps()
    }
}

private struct QuestLocationPreviewPoint: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let title: String
}

private struct AddressSuggestion: Identifiable, Equatable {
    let id: String
    let primaryText: String
    let secondaryText: String?

    var fullText: String {
        let secondary = secondaryText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if secondary.isEmpty {
            return primaryText
        }
        return "\(primaryText), \(secondary)"
    }
}

@MainActor
private final class AddressAutocompleteProvider: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published private(set) var suggestions: [AddressSuggestion] = []
    @Published private(set) var isSearching = false

    private let completer = MKLocalSearchCompleter()
    private var lastQuery = ""

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    func updateQuery(_ rawQuery: String) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query != lastQuery else { return }
        lastQuery = query

        if query.count < 3 {
            clear()
            return
        }

        isSearching = true
        completer.queryFragment = query
    }

    func clear() {
        isSearching = false
        suggestions = []
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        isSearching = false
        suggestions = completer.results.prefix(5).map { result in
            let title = result.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let subtitle = result.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
            return AddressSuggestion(
                id: "\(title)|\(subtitle)",
                primaryText: title.isEmpty ? "Unknown place" : title,
                secondaryText: subtitle.isEmpty ? nil : subtitle
            )
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        isSearching = false
        suggestions = []
        #if DEBUG
        print("[SYSTEM] Apple Maps autocomplete failed: \(error.localizedDescription)")
        #endif
    }
}

// MARK: - HealthKit Quest Types

enum HealthKitQuestType: String, CaseIterable {
    case steps = "steps"
    case distance = "distance"
    case activeEnergy = "activeEnergy"
    case exerciseMinutes = "exerciseMinutes"
    case workoutCount = "workoutCount"
    case standHours = "standHours"
    case sleep = "sleep"
    case water = "water"
    case mindfulness = "mindfulness"

    var displayName: String {
        switch self {
        case .steps: return "Steps"
        case .distance: return "Distance Walked"
        case .activeEnergy: return "Active Calories"
        case .exerciseMinutes: return "Exercise Minutes"
        case .workoutCount: return "Workouts (Activity/Fitness)"
        case .standHours: return "Stand Hours"
        case .sleep: return "Sleep"
        case .water: return "Water Intake"
        case .mindfulness: return "Mindful Minutes"
        }
    }

    var unit: String {
        switch self {
        case .steps: return "steps"
        case .distance: return "km"
        case .activeEnergy: return "kcal"
        case .exerciseMinutes: return "minutes"
        case .workoutCount: return "workouts"
        case .standHours: return "hours"
        case .sleep: return "hours"
        case .water: return "glasses"
        case .mindfulness: return "minutes"
        }
    }

    var identifier: String {
        switch self {
        case .steps: return "HKQuantityTypeIdentifierStepCount"
        case .distance: return "HKQuantityTypeIdentifierDistanceWalkingRunning"
        case .activeEnergy: return "HKQuantityTypeIdentifierActiveEnergyBurned"
        case .exerciseMinutes: return "HKQuantityTypeIdentifierAppleExerciseTime"
        case .workoutCount: return "HKWorkoutType"
        case .standHours: return "HKCategoryTypeIdentifierAppleStandHour"
        case .sleep: return "HKCategoryTypeIdentifierSleepAnalysis"
        case .water: return "HKQuantityTypeIdentifierDietaryWater"
        case .mindfulness: return "HKCategoryTypeIdentifierMindfulSession"
        }
    }
}

#Preview {
    QuestFormSheet(mode: .add)
        .environmentObject(GameEngine.shared)
}
