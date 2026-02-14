//
//  PermissionManagerView.swift
//  GAMELIFE
//
//  [SYSTEM]: Neural Link configuration active.
//  Establish your connections to the System.
//

import SwiftUI

// MARK: - Permission Manager View

/// Settings page for managing all "Neural Link" permissions
struct PermissionManagerView: View {

    // MARK: - Properties

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var permissionManager = PermissionManager.shared
    @StateObject private var healthKitManager = HealthKitManager.shared
    @StateObject private var screenTimeManager = ScreenTimeManager.shared
    @StateObject private var locationManager = LocationManager.shared
    @StateObject private var notificationManager = NotificationManager.shared

    // MARK: - Body

    var body: some View {
        List {
            // Header
            Section {
                VStack(spacing: SystemSpacing.md) {
                    // Brain icon with glow
                    ZStack {
                        Circle()
                            .fill(SystemTheme.primaryBlue.opacity(0.1))
                            .frame(width: 80, height: 80)

                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 40))
                            .foregroundStyle(SystemTheme.primaryBlue)
                    }

                    Text("[SYSTEM]: Neural Link Status")
                        .font(SystemTypography.systemMessage)
                        .foregroundStyle(SystemTheme.primaryBlue)

                    Text("Connect data sources to enable automatic quest tracking and enhanced features")
                        .font(SystemTypography.caption)
                        .foregroundStyle(SystemTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical)
                .listRowBackground(Color.clear)
            }

            // Neural Links
            Section {
                ForEach(NeuralLinkType.betaAvailableCases) { linkType in
                    NeuralLinkRow(
                        type: linkType,
                        status: permissionManager.status(for: linkType),
                        isEnabled: permissionManager.isEnabled(for: linkType),
                        onToggle: { requestPermission(for: linkType) }
                    )
                }
            } header: {
                Text("Available Connections")
            } footer: {
                Text("Tap to connect each Neural Link. Once Vital Signs is connected, tapping it opens the Health app.")
            }

            Section {
                NeuralLinkSignalRow(
                    title: "Vital Signs",
                    connected: permissionManager.healthKitEnabled,
                    lastUpdateText: relativeText(healthKitManager.lastSyncDate),
                    backgroundActive: healthKitManager.backgroundDeliveryEnabled
                )
                if AppFeatureFlags.screenTimeEnabled {
                    NeuralLinkSignalRow(
                        title: "Mind Activity",
                        connected: permissionManager.screenTimeEnabled,
                        lastUpdateText: relativeText(screenTimeManager.lastSyncDate),
                        backgroundActive: screenTimeManager.isUsageMonitoringActive
                    )
                }
                NeuralLinkSignalRow(
                    title: "World Position",
                    connected: permissionManager.locationEnabled,
                    lastUpdateText: relativeText(locationManager.lastTrackingEventDate),
                    backgroundActive: locationManager.isMonitoringActive
                )
                NeuralLinkSignalRow(
                    title: "System Messages",
                    connected: permissionManager.notificationsEnabled,
                    lastUpdateText: relativeText(notificationManager.lastQuestCompletionNotificationDate),
                    backgroundActive: permissionManager.notificationsEnabled
                )
            } header: {
                Text("Connection Confidence")
            } footer: {
                Text("Shows whether each link is connected, recently updating, and actively monitoring in the background/OS pipeline.")
            }

            // What each link does
            Section {
                ForEach(NeuralLinkType.betaAvailableCases) { linkType in
                    NeuralLinkExplanation(type: linkType)
                }
            } header: {
                Text("Neural Link Benefits")
            }

            // Settings button
            Section {
                Button {
                    permissionManager.openSystemSettings()
                } label: {
                    HStack {
                        Image(systemName: "gear")
                            .foregroundStyle(SystemTheme.primaryBlue)

                        Text("Open System Settings")
                            .foregroundStyle(SystemTheme.textPrimary)

                        Spacer()

                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12))
                            .foregroundStyle(SystemTheme.textTertiary)
                    }
                }
            } footer: {
                Text("Manage detailed permissions in iOS Settings")
            }
        }
        .navigationTitle("Neural Links")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task {
                await refreshPermissions()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await refreshPermissions()
            }
        }
        .refreshable {
            await refreshPermissions()
        }
    }

    // MARK: - Actions

    private func requestPermission(for type: NeuralLinkType) {
        Task {
            do {
                if type == .vitalSigns, permissionManager.isEnabled(for: .vitalSigns) {
                    permissionManager.openHealthApp()
                    return
                }

                switch type {
                case .vitalSigns:
                    try await permissionManager.requestHealthKit()
                    if permissionManager.isEnabled(for: .vitalSigns) {
                        permissionManager.openHealthApp()
                    }
                case .mindActivity:
                    try await permissionManager.requestScreenTime()
                case .worldPosition:
                    if permissionManager.status(for: .worldPosition) == .denied {
                        permissionManager.openSystemSettings()
                        return
                    }
                    permissionManager.requestLocation()
                    try await Task.sleep(nanoseconds: 1_200_000_000)
                    permissionManager.checkLocationStatus()
                case .systemMessages:
                    try await permissionManager.requestNotifications()
                }

                if permissionManager.isEnabled(for: type) {
                    SystemMessageHelper.show(SystemMessage(
                        type: .success,
                        title: "Neural Link Connected",
                        message: "\(type.rawValue) is now active"
                    ))
                } else {
                    SystemMessageHelper.showWarning("Enable \(type.rawValue) in Settings")
                }
            } catch {
                // Permission denied - show settings prompt
                SystemMessageHelper.showWarning("Enable \(type.rawValue) in Settings")
            }
        }
    }

    private func refreshPermissions() async {
        await permissionManager.checkAllPermissions()
    }

    private func relativeText(_ date: Date?) -> String {
        guard let date else { return "Never" }
        return date.formatted(.relative(presentation: .named))
    }
}

// MARK: - Neural Link Row

struct NeuralLinkRow: View {
    let type: NeuralLinkType
    let status: PermissionStatus
    let isEnabled: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(type.color.opacity(0.1))
                        .frame(width: 44, height: 44)

                    Image(systemName: iconName(for: type))
                        .font(.system(size: 20))
                        .foregroundStyle(type.color)
                }

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(type.rawValue)
                        .font(SystemTypography.headline)
                        .foregroundStyle(SystemTheme.textPrimary)

                    Text(description(for: type))
                        .font(SystemTypography.captionSmall)
                        .foregroundStyle(SystemTheme.textSecondary)
                }

                Spacer()

                // Status indicator
                StatusIndicator(status: status, isEnabled: isEnabled)
            }
        }
    }

    private func iconName(for type: NeuralLinkType) -> String {
        switch type {
        case .vitalSigns: return "heart.fill"
        case .mindActivity: return "brain.head.profile"
        case .worldPosition: return "location.fill"
        case .systemMessages: return "bell.fill"
        }
    }

    private func description(for type: NeuralLinkType) -> String {
        switch type {
        case .vitalSigns: return "HealthKit data (steps, workouts, sleep)"
        case .mindActivity: return "Screen Time API"
        case .worldPosition: return "Core Location"
        case .systemMessages: return "Push Notifications"
        }
    }
}

// MARK: - Status Indicator

struct StatusIndicator: View {
    let status: PermissionStatus
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: status.icon)
                .font(.system(size: 14))

            Text(status.rawValue)
                .font(SystemTypography.mono(11, weight: .semibold))
        }
        .foregroundStyle(status.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(status.color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Neural Link Explanation

struct NeuralLinkExplanation: View {
    let type: NeuralLinkType

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: iconName(for: type))
                    .font(.system(size: 14))
                    .foregroundStyle(type.color)
                    .frame(width: 20)

                Text(type.rawValue)
                    .font(SystemTypography.mono(12, weight: .bold))
                    .foregroundStyle(type.color)
            }

            ForEach(benefits(for: type), id: \.self) { benefit in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(SystemTheme.successGreen)
                        .frame(width: 16)

                    Text(benefit)
                        .font(SystemTypography.captionSmall)
                        .foregroundStyle(SystemTheme.textSecondary)
                }
            }
        }
    }

    private func iconName(for type: NeuralLinkType) -> String {
        switch type {
        case .vitalSigns: return "heart.fill"
        case .mindActivity: return "brain.head.profile"
        case .worldPosition: return "location.fill"
        case .systemMessages: return "bell.fill"
        }
    }

    private func benefits(for type: NeuralLinkType) -> [String] {
        switch type {
        case .vitalSigns:
            return [
                "Auto-track steps, distance, calories, and hydration",
                "Monitor sleep for VIT stat progress",
                "Auto-complete workout count quests (ex: 3 workouts per week)"
            ]
        case .mindActivity:
            return [
                "Track reading app usage for INT quests",
                "Monitor social media avoidance for WIL",
                "Block distracting apps during Training"
            ]
        case .worldPosition:
            return [
                "Auto-complete gym visit quests",
                "Track outdoor time for VIT",
                "Geofence-based quest triggers"
            ]
        case .systemMessages:
            return [
                "Quest reminder notifications",
                "Level up celebrations",
                "Training session alerts"
            ]
        }
    }
}

private struct NeuralLinkSignalRow: View {
    let title: String
    let connected: Bool
    let lastUpdateText: String
    let backgroundActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(SystemTypography.bodySmall)
                    .foregroundStyle(SystemTheme.textPrimary)
                Spacer()
                Text(connected ? "Connected" : "Not Connected")
                    .font(SystemTypography.mono(11, weight: .semibold))
                    .foregroundStyle(connected ? SystemTheme.successGreen : SystemTheme.warningOrange)
            }

            HStack {
                Text("Last Update")
                    .font(SystemTypography.captionSmall)
                    .foregroundStyle(SystemTheme.textTertiary)
                Spacer()
                Text(lastUpdateText)
                    .font(SystemTypography.captionSmall)
                    .foregroundStyle(SystemTheme.textSecondary)
            }

            HStack {
                Text("Background Active")
                    .font(SystemTypography.captionSmall)
                    .foregroundStyle(SystemTheme.textTertiary)
                Spacer()
                Text(backgroundActive ? "Yes" : "No")
                    .font(SystemTypography.captionSmall)
                    .foregroundStyle(backgroundActive ? SystemTheme.successGreen : SystemTheme.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PermissionManagerView()
    }
}
