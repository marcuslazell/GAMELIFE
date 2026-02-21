//
//  SettingsView.swift
//  GAMELIFE
//
//  [SYSTEM]: Configuration interface accessed.
//  Customize your System experience.
//

import SwiftUI

// MARK: - Settings View

/// Settings page accessed via gear icon on Status tab
struct SettingsView: View {

    // MARK: - Properties

    @EnvironmentObject var gameEngine: GameEngine
    @AppStorage("defaultTab") private var defaultTab: Int = 0
    @AppStorage("useSystemAppearance") private var useSystemAppearance = true
    @AppStorage("preferDarkMode") private var preferDarkMode = true
    @AppStorage("questCompletionNotificationMode") private var questCompletionNotificationMode = NotificationManager.QuestCompletionNotificationMode.immediate.rawValue
    @AppStorage("deathMechanicEnabled") private var deathMechanicEnabled = true
    @State private var showResetConfirmation = false
    @State private var showDeleteConfirmation = false

    // MARK: - Body

    var body: some View {
        List {
            // Player Section
            Section {
                NavigationLink {
                    PlayerProfileView()
                } label: {
                    HStack {
                        ZStack {
                            Circle()
                                .fill(gameEngine.player.rank.glowColor.opacity(0.2))
                                .frame(width: 44, height: 44)

                            Text(gameEngine.player.rank.rawValue)
                                .font(SystemTypography.mono(14, weight: .bold))
                                .foregroundStyle(gameEngine.player.rank.glowColor)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(gameEngine.player.name)
                                .font(SystemTypography.headline)
                                .foregroundStyle(SystemTheme.textPrimary)

                            Text("Lv. \(gameEngine.player.level) \(gameEngine.player.title)")
                                .font(SystemTypography.caption)
                                .foregroundStyle(SystemTheme.textSecondary)
                        }

                        Spacer()
                    }
                }
            } header: {
                Text("Hunter Profile")
            }

            // Preferences Section
            Section {
                Picker("Default Tab", selection: $defaultTab) {
                    Text("Status").tag(0)
                    Text("Quests").tag(1)
                    Text("Training").tag(2)
                    Text("Bosses").tag(3)
                    Text("Shop").tag(4)
                }

                Toggle("Use System Appearance", isOn: $useSystemAppearance)

                if !useSystemAppearance {
                    Toggle("Dark Mode", isOn: $preferDarkMode)
                }

                Picker("Quest Completion Alerts", selection: $questCompletionNotificationMode) {
                    ForEach(NotificationManager.QuestCompletionNotificationMode.allCases) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
                .onChange(of: questCompletionNotificationMode) { _, rawValue in
                    let mode = NotificationManager.QuestCompletionNotificationMode(rawValue: rawValue) ?? .immediate
                    NotificationManager.shared.questCompletionNotificationMode = mode
                }

                Toggle("Death Mechanic Penalties", isOn: $deathMechanicEnabled)
            } header: {
                Text("Preferences")
            } footer: {
                Text("Set your default tab, appearance, alerts, and death penalties in one place. Turning off death penalties does not stop HP loss.")
            }

            // Neural Links Section
            Section {
                NavigationLink {
                    PermissionManagerView()
                } label: {
                    HStack {
                        Label("Neural Links", systemImage: "brain.head.profile")
                            .foregroundStyle(SystemTheme.textPrimary)

                        Spacer()

                        // Connection status indicator
                        ConnectionStatusBadge()
                    }
                }
            } header: {
                Text("Data Connections")
            } footer: {
                Text("Connect GAMELIFE to health and location data")
            }

            // Statistics Section
            Section {
                StatRow(label: "Quests Completed", value: "\(gameEngine.player.completedQuestCount)")
                StatRow(label: "Bosses Defeated", value: "\(gameEngine.player.defeatedBossCount)")
                StatRow(label: "Training Sessions", value: "\(gameEngine.player.dungeonsClearedCount)")
                StatRow(label: "Current Streak", value: "\(gameEngine.player.currentStreak) days")
                StatRow(label: "Longest Streak", value: "\(gameEngine.player.longestStreak) days")
                StatRow(label: "Total XP Earned", value: "\(gameEngine.player.totalXP)")
            } header: {
                Text("Statistics")
            }

            // Danger Zone Section
            Section {
                Button {
                    showResetConfirmation = true
                } label: {
                    Label("Reset Quest Progress", systemImage: "arrow.counterclockwise")
                        .foregroundStyle(SystemTheme.warningOrange)
                }

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete All Data", systemImage: "trash.fill")
                }
            } header: {
                Text("Danger Zone")
            } footer: {
                Text("These actions cannot be undone")
            }

            // About Section
            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundStyle(SystemTheme.textSecondary)
                }

                if let aboutURL = URL(string: "https://gamelife.app") {
                    Link(destination: aboutURL) {
                        Label("About GAMELIFE", systemImage: "info.circle")
                    }
                }

                if let privacyURL = URL(string: "https://gamelife.app/privacy") {
                    Link(destination: privacyURL) {
                        Label("Privacy Policy", systemImage: "hand.raised.fill")
                    }
                }
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Reset Quest Progress?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                resetDailyQuests()
            }
        } message: {
            Text("This will reset progress on your current quests for the active cycle.")
        }
        .alert("Delete All Data?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Everything", role: .destructive) {
                deleteAllData()
            }
        } message: {
            Text("This will permanently delete your player profile, all quests, bosses, and progress. This action cannot be undone.")
        }
    }

    // MARK: - Actions

    private func resetDailyQuests() {
        gameEngine.resetQuestProgressManually()

        SystemMessageHelper.showInfo("Quests Reset", "Quest progress has been reset for the current cycle.")
    }

    private func deleteAllData() {
        // Clear persisted app domain and reset in-memory state.
        SettingsManager.shared.resetAllSettings()

        gameEngine.startFreshProfile(named: "Hunter")

        MarketplaceManager.shared.resetForFreshStart()
        NotificationManager.shared.clearAllQuestReminders()
        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")

        SystemMessageHelper.show(SystemMessage(
            type: .critical,
            title: "Data Deleted",
            message: "All data has been erased and reset."
        ))
    }
}

// MARK: - Connection Status Badge

struct ConnectionStatusBadge: View {
    @StateObject private var permissionManager = PermissionManager.shared

    private var connectedCount: Int {
        var count = 0
        if permissionManager.healthKitEnabled { count += 1 }
        if AppFeatureFlags.screenTimeEnabled && permissionManager.screenTimeEnabled { count += 1 }
        if permissionManager.locationEnabled { count += 1 }
        if permissionManager.notificationsEnabled { count += 1 }
        return count
    }

    private var totalCount: Int {
        NeuralLinkType.betaAvailableCases.count
    }

    var body: some View {
        Text("\(connectedCount)/\(totalCount)")
            .font(SystemTypography.mono(12, weight: .semibold))
            .foregroundStyle(connectedCount == totalCount ? SystemTheme.successGreen : SystemTheme.textTertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                (connectedCount == totalCount ? SystemTheme.successGreen : SystemTheme.textTertiary).opacity(0.1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .onAppear {
                Task {
                    await permissionManager.checkAllPermissions()
                }
            }
    }
}

// MARK: - Stat Row

struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(SystemTheme.textSecondary)
            Spacer()
            Text(value)
                .font(SystemTypography.mono(14, weight: .semibold))
                .foregroundStyle(SystemTheme.textPrimary)
        }
    }
}

// MARK: - Player Profile View

struct PlayerProfileView: View {
    @EnvironmentObject var gameEngine: GameEngine
    @State private var editedName: String = ""
    @State private var editedTitle: String = ""
    @State private var isEditing = false

    var body: some View {
        List {
            Section {
                if isEditing {
                    TextField("Hunter Name", text: $editedName)
                        .font(SystemTypography.body)
                } else {
                    HStack {
                        Text("Name")
                            .foregroundStyle(SystemTheme.textSecondary)
                        Spacer()
                        Text(gameEngine.player.name)
                            .font(SystemTypography.headline)
                    }
                }

                HStack {
                    Text("Rank")
                        .foregroundStyle(SystemTheme.textSecondary)
                    Spacer()
                    Text(gameEngine.player.rank.rawValue)
                        .font(SystemTypography.mono(14, weight: .bold))
                        .foregroundStyle(gameEngine.player.rank.glowColor)
                }

                if isEditing {
                    Picker("Title", selection: $editedTitle) {
                        ForEach(gameEngine.player.unlockedTitles, id: \.self) { title in
                            Text(title).tag(title)
                        }
                    }
                } else {
                    HStack {
                        Text("Title")
                            .foregroundStyle(SystemTheme.textSecondary)
                        Spacer()
                        Text(gameEngine.player.title)
                    }
                }

                HStack {
                    Text("Level")
                        .foregroundStyle(SystemTheme.textSecondary)
                    Spacer()
                    Text("\(gameEngine.player.level)")
                        .font(SystemTypography.mono(14, weight: .bold))
                        .foregroundStyle(SystemTheme.primaryBlue)
                }

                HStack {
                    Text("Power Level")
                        .foregroundStyle(SystemTheme.textSecondary)
                    Spacer()
                    Text("\(gameEngine.player.powerLevel)")
                        .font(SystemTypography.mono(14, weight: .bold))
                }
            } header: {
                Text("Profile")
            }

            Section {
                HStack {
                    Text("Total XP")
                        .foregroundStyle(SystemTheme.textSecondary)
                    Spacer()
                    Text("\(gameEngine.player.totalXP)")
                        .font(SystemTypography.mono(14, weight: .semibold))
                        .foregroundStyle(SystemTheme.primaryBlue)
                }

                HStack {
                    Text("Gold")
                        .foregroundStyle(SystemTheme.textSecondary)
                    Spacer()
                    Text("\(gameEngine.player.gold)")
                        .font(SystemTypography.mono(14, weight: .semibold))
                        .foregroundStyle(SystemTheme.goldColor)
                }

                HStack {
                    Text("Shadow Soldiers")
                        .foregroundStyle(SystemTheme.textSecondary)
                    Spacer()
                    Text("\(gameEngine.player.shadowSoldiers.count)")
                        .font(SystemTypography.mono(14, weight: .semibold))
                }

                HStack {
                    Text("Member Since")
                        .foregroundStyle(SystemTheme.textSecondary)
                    Spacer()
                    Text(gameEngine.player.createdAt, style: .date)
                        .font(SystemTypography.caption)
                }
            } header: {
                Text("Progress")
            }

            if !gameEngine.player.unlockedTitles.isEmpty {
                Section {
                    ForEach(gameEngine.player.unlockedTitles, id: \.self) { title in
                        HStack {
                            Image(systemName: "text.badge.star")
                                .foregroundStyle(SystemTheme.goldColor)
                            Text(title)
                            Spacer()
                            if title == gameEngine.player.title {
                                Text("Active")
                                    .font(SystemTypography.captionSmall)
                                    .foregroundStyle(SystemTheme.successGreen)
                            }
                        }
                    }
                } header: {
                    Text("Unlocked Titles")
                }
            }
        }
        .navigationTitle("Hunter Profile")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isEditing ? "Save" : "Edit") {
                    if isEditing {
                        saveProfile()
                    } else {
                        editedName = gameEngine.player.name
                        editedTitle = gameEngine.player.title
                    }
                    isEditing.toggle()
                }
            }
        }
    }

    private func saveProfile() {
        gameEngine.player.name = editedName.trimmingCharacters(in: .whitespaces)
        gameEngine.player.title = editedTitle
        gameEngine.save()
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environmentObject(GameEngine.shared)
}
