//
//  FirstLaunchSetupView.swift
//  GAMELIFE
//
//  [SYSTEM]: Awakening sequence initiated.
//  A new Player has been detected.
//

import SwiftUI

// MARK: - First Launch Setup

struct FirstLaunchSetupView: View {
    @EnvironmentObject var gameEngine: GameEngine
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var permissionManager = PermissionManager.shared

    let onComplete: () -> Void

    @State private var step: SetupStep = .name
    @State private var playerName = ""
    @State private var didInitializeProfile = false

    @State private var showBossSheet = false
    @State private var showQuestSheet = false
    @State private var isConnectingAll = false

    // Animation states
    @State private var showContent = false
    @State private var glowIntensity: Double = 0.5

    private var trimmedName: String {
        playerName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var bossCount: Int {
        gameEngine.activeBossFights.count
    }

    private var questCount: Int {
        gameEngine.dailyQuests.count
    }

    var body: some View {
        ZStack {
            // Background
            SystemTheme.backgroundPrimary
                .ignoresSafeArea()

            // Animated particles
            ParticleFieldView()
                .opacity(0.3)

            // Main content
            VStack(spacing: SystemSpacing.lg) {
                if step == .name {
                    nameStep
                } else {
                    setupHeader

                    Spacer(minLength: SystemSpacing.sm)

                    VStack(spacing: SystemSpacing.lg) {
                        Group {
                            switch step {
                            case .name:
                                EmptyView()
                            case .permissions:
                                permissionsStep
                            case .boss:
                                bossStep
                            case .quest:
                                questStep
                            case .stats:
                                statsStep
                            case .shop:
                                shopStep
                            }
                        }

                        footerControls
                    }

                    Spacer(minLength: SystemSpacing.sm)
                }
            }
            .padding(SystemSpacing.md)
        }
        .sheet(isPresented: $showBossSheet) {
            BossFormSheet()
                .environmentObject(gameEngine)
        }
        .sheet(isPresented: $showQuestSheet) {
            QuestFormSheet(mode: .add)
                .environmentObject(gameEngine)
        }
        .onAppear {
            playerName = gameEngine.player.name == "Hunter" ? "" : gameEngine.player.name
            Task {
                await permissionManager.checkAllPermissions()
            }
            // Start glow animation
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                glowIntensity = 1.0
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await permissionManager.checkAllPermissions()
            }
        }
    }

    // MARK: - Setup Header

    private var setupHeader: some View {
        HStack(spacing: SystemSpacing.sm) {
            Button {
                goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(step == .name ? SystemTheme.textTertiary : SystemTheme.primaryBlue)
                    .frame(width: 36, height: 36)
                    .background(SystemTheme.backgroundSecondary)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(SystemTheme.primaryBlue.opacity(0.3), lineWidth: 1)
                    )
            }
            .disabled(step == .name)
            .opacity(step == .name ? 0.4 : 1.0)

            VStack(spacing: 2) {
                Text("[SYSTEM]")
                    .font(SystemTypography.mono(10, weight: .bold))
                    .foregroundStyle(SystemTheme.primaryBlue)

                Text(step.title)
                    .font(SystemTypography.mono(15, weight: .bold))
                    .foregroundStyle(SystemTheme.textPrimary)
            }
            .frame(maxWidth: .infinity)

            // Progress indicator
            ZStack {
                Circle()
                    .stroke(SystemTheme.backgroundTertiary, lineWidth: 3)
                    .frame(width: 36, height: 36)

                Circle()
                    .trim(from: 0, to: Double(step.index) / Double(SetupStep.allCases.count))
                    .stroke(SystemTheme.primaryBlue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 36, height: 36)
                    .rotationEffect(.degrees(-90))

                Text("\(step.index)")
                    .font(SystemTypography.mono(12, weight: .bold))
                    .foregroundStyle(SystemTheme.primaryBlue)
            }
            .glow(color: SystemTheme.primaryBlue.opacity(0.3), radius: 5)
        }
    }

    // MARK: - Name Step (Awakening)

    private var nameStep: some View {
        VStack(spacing: 40) {
            Spacer()

            // System notification box
            VStack(spacing: 24) {
                // System icon
                Image(systemName: "diamond.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(SystemTheme.primaryBlue)
                    .glow(color: SystemTheme.primaryBlue, radius: 15)

                // Main message
                VStack(spacing: 12) {
                    Text("[SYSTEM]")
                        .font(SystemTypography.mono(14, weight: .bold))
                        .foregroundStyle(SystemTheme.primaryBlue)

                    Text("You are qualified")
                        .font(SystemTypography.titleMedium)
                        .foregroundStyle(SystemTheme.textPrimary)

                    Text("to be a")
                        .font(SystemTypography.body)
                        .foregroundStyle(SystemTheme.textSecondary)

                    Text("PLAYER")
                        .font(SystemTypography.titleLarge)
                        .foregroundStyle(SystemTheme.primaryBlue)
                        .glow(color: SystemTheme.primaryBlue, radius: 10)
                }

                Divider()
                    .background(SystemTheme.borderPrimary)

                // Name input
                VStack(spacing: 8) {
                    Text("Enter your name, Hunter.")
                        .font(SystemTypography.systemMessage)
                        .foregroundStyle(SystemTheme.textSecondary)

                    TextField("", text: $playerName, prompt: Text("Your name...").foregroundStyle(SystemTheme.textTertiary))
                        .font(SystemTypography.mono(20, weight: .semibold))
                        .foregroundStyle(SystemTheme.textPrimary)
                        .multilineTextAlignment(.center)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .padding()
                        .background(SystemTheme.backgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: SystemRadius.medium))
                        .overlay(
                            RoundedRectangle(cornerRadius: SystemRadius.medium)
                                .stroke(SystemTheme.primaryBlue.opacity(0.5), lineWidth: 1)
                        )
                }
            }
            .padding(32)
            .background(SystemTheme.backgroundTertiary.opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: SystemRadius.large))
            .overlay(
                RoundedRectangle(cornerRadius: SystemRadius.large)
                    .stroke(SystemTheme.primaryBlue.opacity(glowIntensity), lineWidth: 2)
            )
            .glow(color: SystemTheme.primaryBlue.opacity(0.3), radius: 20)

            // Accept button
            Button {
                initializeProfileAndAdvance()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("ACCEPT")
                        .font(SystemTypography.mono(16, weight: .bold))
                }
                .foregroundStyle(trimmedName.isEmpty ? SystemTheme.textTertiary : SystemTheme.backgroundPrimary)
                .padding(.horizontal, 48)
                .padding(.vertical, 16)
                .background(trimmedName.isEmpty ? SystemTheme.backgroundTertiary : SystemTheme.primaryBlue)
                .clipShape(Capsule())
                .glow(color: trimmedName.isEmpty ? .clear : SystemTheme.primaryBlue, radius: 10)
            }
            .disabled(trimmedName.isEmpty)

            Spacer()
        }
    }

    // MARK: - Permissions Step

    private var permissionsStep: some View {
        setupCard(
            icon: "brain.head.profile",
            title: "NEURAL LINKS",
            color: SystemTheme.primaryPurple
        ) {
            VStack(alignment: .leading, spacing: SystemSpacing.md) {
                Text("Connect to the System for automatic quest tracking. These links enhance your experience but are optional.")
                    .font(SystemTypography.caption)
                    .foregroundStyle(SystemTheme.textSecondary)

                VStack(spacing: SystemSpacing.sm) {
                    ForEach(NeuralLinkType.betaAvailableCases) { type in
                        OnboardingPermissionRow(
                            type: type,
                            status: permissionManager.status(for: type),
                            isEnabled: permissionManager.isEnabled(for: type),
                            action: { requestPermission(type) }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Boss Step

    private var bossStep: some View {
        setupCard(
            icon: "bolt.shield.fill",
            title: "CREATE YOUR BOSS",
            color: SystemTheme.criticalRed
        ) {
            VStack(alignment: .leading, spacing: SystemSpacing.md) {
                Text("Bosses are the dragons you must slay. Large goals with HP bars that decrease as you complete daily quests.")
                    .font(SystemTypography.caption)
                    .foregroundStyle(SystemTheme.textSecondary)

                HStack(spacing: 8) {
                    ExampleTag(text: "Lose 20 lbs", color: SystemTheme.statStrength)
                    ExampleTag(text: "Ship a project", color: SystemTheme.statIntelligence)
                }

                if bossCount > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(SystemTheme.successGreen)
                        Text("\(bossCount) boss created")
                            .font(SystemTypography.mono(12, weight: .semibold))
                            .foregroundStyle(SystemTheme.successGreen)
                    }
                    .padding(.top, 4)
                } else {
                    Text("\"Every hunter needs a worthy adversary.\"")
                        .font(SystemTypography.caption)
                        .foregroundStyle(SystemTheme.textTertiary)
                        .italic()
                }
            }
        }
    }

    // MARK: - Quest Step

    private var questStep: some View {
        setupCard(
            icon: "list.bullet.rectangle",
            title: "DAILY QUESTS",
            color: SystemTheme.successGreen
        ) {
            VStack(alignment: .leading, spacing: SystemSpacing.md) {
                Text("Create at least one daily quest. Start with the \"Insultingly Low Bar\" - something so easy you can't say no.")
                    .font(SystemTypography.caption)
                    .foregroundStyle(SystemTheme.textSecondary)

                VStack(alignment: .leading, spacing: 4) {
                    QuestExampleRow(text: "1 pushup", stat: .strength)
                    QuestExampleRow(text: "Read 1 page", stat: .intelligence)
                    QuestExampleRow(text: "Drink water", stat: .vitality)
                }

                if questCount > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(SystemTheme.successGreen)
                        Text("\(questCount) quest\(questCount == 1 ? "" : "s") ready")
                            .font(SystemTypography.mono(12, weight: .semibold))
                            .foregroundStyle(SystemTheme.successGreen)
                    }
                    .padding(.top, 4)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(SystemTheme.warningOrange)
                        Text("At least one quest required")
                            .font(SystemTypography.mono(12, weight: .semibold))
                            .foregroundStyle(SystemTheme.warningOrange)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - Stats Step

    private var statsStep: some View {
        setupCard(
            icon: "hexagon",
            title: "YOUR STATS",
            color: SystemTheme.primaryBlue
        ) {
            VStack(alignment: .leading, spacing: SystemSpacing.md) {
                Text("Each quest rewards XP and stat growth. As you level up, your power increases across six attributes.")
                    .font(SystemTypography.caption)
                    .foregroundStyle(SystemTheme.textSecondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: SystemSpacing.sm) {
                    StatHintRow(stat: .strength, text: "Physical power")
                    StatHintRow(stat: .vitality, text: "Health & recovery")
                    StatHintRow(stat: .intelligence, text: "Knowledge & focus")
                    StatHintRow(stat: .willpower, text: "Discipline")
                    StatHintRow(stat: .agility, text: "Speed & action")
                    StatHintRow(stat: .spirit, text: "Inner peace")
                }

                Text("\"The weak have no rights. The strong define them.\"")
                    .font(SystemTypography.caption)
                    .foregroundStyle(SystemTheme.textTertiary)
                    .italic()
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Shop Step

    private var shopStep: some View {
        setupCard(
            icon: "bag.fill",
            title: "REWARD SHOP",
            color: SystemTheme.goldColor
        ) {
            VStack(alignment: .leading, spacing: SystemSpacing.md) {
                Text("Spend earned Gold on real-world rewards. Define your own prizes to make progress tangible.")
                    .font(SystemTypography.caption)
                    .foregroundStyle(SystemTheme.textSecondary)

                VStack(alignment: .leading, spacing: 6) {
                    ShopExampleRow(gold: 500, text: "1 hour guilt-free gaming")
                    ShopExampleRow(gold: 1000, text: "Order your favorite food")
                    ShopExampleRow(gold: 2500, text: "Buy something nice")
                }

                Text("\"Gold is the measure of a hunter's dedication.\"")
                    .font(SystemTypography.caption)
                    .foregroundStyle(SystemTheme.textTertiary)
                    .italic()
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Footer Controls

    private var footerControls: some View {
        VStack(spacing: SystemSpacing.sm) {
            switch step {
            case .name:
                EmptyView()

            case .permissions:
                Button {
                    connectAllPermissions()
                } label: {
                    HStack(spacing: 8) {
                        if isConnectingAll {
                            ProgressView()
                                .tint(SystemTheme.primaryPurple)
                        }
                        Text(isConnectingAll ? "ESTABLISHING LINKS..." : "CONNECT ALL")
                            .font(SystemTypography.mono(13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(SystemTheme.primaryPurple.opacity(0.15))
                    .foregroundStyle(SystemTheme.primaryPurple)
                    .clipShape(RoundedRectangle(cornerRadius: SystemRadius.medium))
                    .overlay(
                        RoundedRectangle(cornerRadius: SystemRadius.medium)
                            .stroke(SystemTheme.primaryPurple.opacity(0.3), lineWidth: 1)
                    )
                }
                .disabled(isConnectingAll)

                primaryButton(title: "CONTINUE", icon: "arrow.right") {
                    goForward()
                }

            case .boss:
                Button {
                    showBossSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text("CREATE BOSS")
                            .font(SystemTypography.mono(13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(SystemTheme.criticalRed.opacity(0.15))
                    .foregroundStyle(SystemTheme.criticalRed)
                    .clipShape(RoundedRectangle(cornerRadius: SystemRadius.medium))
                    .overlay(
                        RoundedRectangle(cornerRadius: SystemRadius.medium)
                            .stroke(SystemTheme.criticalRed.opacity(0.3), lineWidth: 1)
                    )
                }

                HStack(spacing: SystemSpacing.sm) {
                    Button("Skip for now") {
                        goForward()
                    }
                    .font(SystemTypography.caption)
                    .foregroundStyle(SystemTheme.textTertiary)
                    .frame(maxWidth: .infinity)

                    primaryButton(title: "CONTINUE", icon: "arrow.right") {
                        goForward()
                    }
                    .frame(maxWidth: .infinity)
                }

            case .quest:
                Button {
                    showQuestSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text("CREATE QUEST")
                            .font(SystemTypography.mono(13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(SystemTheme.successGreen.opacity(0.15))
                    .foregroundStyle(SystemTheme.successGreen)
                    .clipShape(RoundedRectangle(cornerRadius: SystemRadius.medium))
                    .overlay(
                        RoundedRectangle(cornerRadius: SystemRadius.medium)
                            .stroke(SystemTheme.successGreen.opacity(0.3), lineWidth: 1)
                    )
                }

                HStack(spacing: SystemSpacing.sm) {
                    Button("Skip for now") {
                        goForward()
                    }
                    .font(SystemTypography.caption)
                    .foregroundStyle(SystemTheme.textTertiary)
                    .frame(maxWidth: .infinity)

                    primaryButton(title: "CONTINUE", icon: "arrow.right") {
                        goForward()
                    }
                    .disabled(questCount == 0)
                    .opacity(questCount == 0 ? 0.5 : 1.0)
                    .frame(maxWidth: .infinity)
                }

            case .stats:
                primaryButton(title: "CONTINUE", icon: "arrow.right") {
                    goForward()
                }

            case .shop:
                primaryButton(title: "ENTER THE SYSTEM", icon: "play.fill") {
                    onComplete()
                }
            }
        }
    }

    // MARK: - Helper Views

    private func setupCard<Content: View>(
        icon: String,
        title: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: SystemSpacing.md) {
            HStack(spacing: SystemSpacing.sm) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 40, height: 40)

                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundStyle(color)
                }
                .glow(color: color.opacity(0.3), radius: 8)

                Text(title)
                    .font(SystemTypography.mono(14, weight: .bold))
                    .foregroundStyle(color)
            }

            content()
        }
        .padding(SystemSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SystemTheme.backgroundTertiary.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: SystemRadius.large))
        .overlay(
            RoundedRectangle(cornerRadius: SystemRadius.large)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
        .glow(color: color.opacity(0.15), radius: 10)
    }

    private func primaryButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(SystemTypography.mono(14, weight: .bold))
                Image(systemName: icon)
            }
            .foregroundStyle(SystemTheme.backgroundPrimary)
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                LinearGradient(
                    colors: [SystemTheme.primaryBlue, SystemTheme.primaryPurple],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: SystemRadius.medium))
            .glow(color: SystemTheme.primaryBlue.opacity(0.4), radius: 8)
        }
    }

    // MARK: - Actions

    private func initializeProfileAndAdvance() {
        guard !trimmedName.isEmpty else { return }

        if didInitializeProfile {
            gameEngine.player.name = trimmedName
            gameEngine.save()
        } else {
            gameEngine.startFreshProfile(named: trimmedName)
            didInitializeProfile = true
        }

        withAnimation(.easeInOut(duration: 0.3)) {
            goForward()
        }
    }

    private func goForward() {
        guard let next = step.next else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            step = next
        }
    }

    private func goBack() {
        guard let previous = step.previous else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            step = previous
        }
    }

    private func connectAllPermissions() {
        Task {
            isConnectingAll = true
            for linkType in NeuralLinkType.betaAvailableCases {
                await requestPermissionAsync(linkType)
            }
            await permissionManager.checkAllPermissions()
            isConnectingAll = false
        }
    }

    private func requestPermission(_ type: NeuralLinkType) {
        Task {
            await requestPermissionAsync(type)
            await permissionManager.checkAllPermissions()
        }
    }

    @MainActor
    private func requestPermissionAsync(_ type: NeuralLinkType) async {
        switch type {
        case .vitalSigns:
            do {
                try await permissionManager.requestHealthKit()
            } catch {}
        case .mindActivity:
            do {
                try await permissionManager.requestScreenTime()
            } catch {}
        case .worldPosition:
            if permissionManager.status(for: .worldPosition) == .denied {
                permissionManager.openSystemSettings()
            } else {
                permissionManager.requestLocation()
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                permissionManager.checkLocationStatus()
            }
        case .systemMessages:
            do {
                try await permissionManager.requestNotifications()
            } catch {}
        }
    }
}

// MARK: - Setup Step

private enum SetupStep: Int, CaseIterable {
    case name
    case permissions
    case boss
    case quest
    case stats
    case shop

    var title: String {
        switch self {
        case .name: return "AWAKENING"
        case .permissions: return "NEURAL LINKS"
        case .boss: return "BOSS TARGET"
        case .quest: return "DAILY QUESTS"
        case .stats: return "STATS OVERVIEW"
        case .shop: return "REWARD SHOP"
        }
    }

    var index: Int { rawValue + 1 }

    var next: SetupStep? {
        SetupStep(rawValue: rawValue + 1)
    }

    var previous: SetupStep? {
        SetupStep(rawValue: rawValue - 1)
    }
}

// MARK: - Supporting Views

private struct OnboardingPermissionRow: View {
    let type: NeuralLinkType
    let status: PermissionStatus
    let isEnabled: Bool
    let action: () -> Void

    private var actionTitle: String {
        if isEnabled { return "LINKED" }
        if status == .denied { return "SETTINGS" }
        if status == .unavailable { return "N/A" }
        return "LINK"
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(type.color.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(type.color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(type.rawValue)
                    .font(SystemTypography.mono(12, weight: .semibold))
                    .foregroundStyle(SystemTheme.textPrimary)

                Text(status.rawValue)
                    .font(SystemTypography.captionSmall)
                    .foregroundStyle(status.color)
            }

            Spacer()

            Button(action: action) {
                Text(actionTitle)
                    .font(SystemTypography.mono(10, weight: .bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isEnabled ? SystemTheme.successGreen.opacity(0.15) : type.color.opacity(0.15))
                    .foregroundStyle(isEnabled ? SystemTheme.successGreen : type.color)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(isEnabled ? SystemTheme.successGreen.opacity(0.3) : type.color.opacity(0.3), lineWidth: 1)
                    )
            }
            .disabled(status == .unavailable || isEnabled)
        }
        .padding(.vertical, 4)
    }

    private var icon: String {
        switch type {
        case .vitalSigns: return "heart.fill"
        case .mindActivity: return "brain.head.profile"
        case .worldPosition: return "location.fill"
        case .systemMessages: return "bell.fill"
        }
    }
}

private struct ExampleTag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(SystemTypography.mono(11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
    }
}

private struct QuestExampleRow: View {
    let text: String
    let stat: StatType

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(SystemTheme.successGreen)

            Text(text)
                .font(SystemTypography.caption)
                .foregroundStyle(SystemTheme.textSecondary)

            Spacer()

            Text(stat.rawValue)
                .font(SystemTypography.mono(10, weight: .semibold))
                .foregroundStyle(stat.color)
        }
    }
}

private struct StatHintRow: View {
    let stat: StatType
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: stat.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(stat.color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(stat.rawValue)
                    .font(SystemTypography.mono(11, weight: .bold))
                    .foregroundStyle(stat.color)

                Text(text)
                    .font(SystemTypography.captionSmall)
                    .foregroundStyle(SystemTheme.textTertiary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct ShopExampleRow: View {
    let gold: Int
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(SystemTheme.goldColor)

                Text("\(gold)")
                    .font(SystemTypography.mono(11, weight: .bold))
                    .foregroundStyle(SystemTheme.goldColor)
            }
            .frame(width: 60, alignment: .leading)

            Text("→")
                .foregroundStyle(SystemTheme.textTertiary)

            Text(text)
                .font(SystemTypography.caption)
                .foregroundStyle(SystemTheme.textSecondary)

            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    FirstLaunchSetupView(onComplete: {})
        .environmentObject(GameEngine.shared)
}
