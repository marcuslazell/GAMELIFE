//
//  OnboardingView.swift
//  GAMELIFE
//
//  [SYSTEM]: Awakening sequence initiated.
//  A new Player has been detected.
//

import SwiftUI
import Combine

// MARK: - Onboarding View

/// The awakening sequence - when a user becomes a Player
struct OnboardingView: View {
    @Binding var isOnboardingComplete: Bool
    @StateObject private var viewModel = OnboardingViewModel()

    var body: some View {
        ZStack {
            // Background
            SystemTheme.backgroundPrimary
                .ignoresSafeArea()

            // Animated particles
            ParticleFieldView()
                .opacity(0.3)

            // Main content
            VStack {
                Spacer()

                switch viewModel.currentPhase {
                case .awakening:
                    AwakeningPhaseView(onAccept: viewModel.acceptAwakening)

                case .nameEntry:
                    NameEntryPhaseView(
                        name: $viewModel.playerName,
                        onContinue: viewModel.proceedToClassSelection
                    )

                case .classSelection:
                    ClassSelectionPhaseView(
                        selectedClass: $viewModel.selectedClass,
                        onContinue: viewModel.proceedToOrigin
                    )

                case .originStory:
                    OriginStoryPhaseView(
                        originStory: $viewModel.originStory,
                        onContinue: viewModel.proceedToStats
                    )

                case .initialStats:
                    InitialStatsPhaseView(onContinue: viewModel.proceedToSetupQuests)

                case .setupQuests:
                    SetupQuestsPhaseView(onContinue: viewModel.completeOnboarding)

                case .complete:
                    EmptyView()
                }

                Spacer()
            }
            .padding()
        }
        .onChange(of: viewModel.currentPhase) { _, newPhase in
            if newPhase == .complete {
                withAnimation(.easeOut(duration: 0.5)) {
                    isOnboardingComplete = true
                }
            }
        }
    }
}

// MARK: - Onboarding View Model

class OnboardingViewModel: ObservableObject {
    enum Phase {
        case awakening
        case nameEntry
        case classSelection    // NEW: Choose your path
        case originStory
        case initialStats
        case setupQuests       // NEW: Neural Link permissions
        case complete
    }

    @Published var currentPhase: Phase = .awakening
    @Published var playerName: String = ""
    @Published var originStory: String = ""
    @Published var selectedClass: PlayerClass = .scholar

    func acceptAwakening() {
        withAnimation(.easeInOut(duration: 0.5)) {
            currentPhase = .nameEntry
        }
    }

    func proceedToClassSelection() {
        guard !playerName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.5)) {
            currentPhase = .classSelection
        }
    }

    func proceedToOrigin() {
        withAnimation(.easeInOut(duration: 0.5)) {
            currentPhase = .originStory
        }
    }

    func proceedToStats() {
        withAnimation(.easeInOut(duration: 0.5)) {
            currentPhase = .initialStats
        }
    }

    func proceedToSetupQuests() {
        withAnimation(.easeInOut(duration: 0.5)) {
            currentPhase = .setupQuests
        }
    }

    func completeOnboarding() {
        // Save player data
        let player = Player(name: playerName, originStory: originStory)
        PlayerDataManager.shared.savePlayer(player)

        // Set initial quests based on class
        let initialQuests = selectedClass.defaultQuests
        GameEngine.shared.dailyQuests = initialQuests
        GameEngine.shared.save()

        withAnimation(.easeInOut(duration: 0.8)) {
            currentPhase = .complete
        }
    }
}

// MARK: - Player Class

enum PlayerClass: String, CaseIterable, Codable {
    case scholar = "Scholar"
    case athlete = "Athlete"
    case creator = "Creator"

    var description: String {
        switch self {
        case .scholar: return "The path of knowledge. Master your mind through learning and focus."
        case .athlete: return "The path of strength. Transform your body through discipline and training."
        case .creator: return "The path of creation. Build your legacy through projects and productivity."
        }
    }

    var icon: String {
        switch self {
        case .scholar: return "book.fill"
        case .athlete: return "figure.strengthtraining.traditional"
        case .creator: return "hammer.fill"
        }
    }

    var primaryStats: [StatType] {
        switch self {
        case .scholar: return [.intelligence, .willpower, .spirit]
        case .athlete: return [.strength, .vitality, .agility]
        case .creator: return [.intelligence, .willpower, .agility]
        }
    }

    var color: Color {
        switch self {
        case .scholar: return SystemTheme.statIntelligence
        case .athlete: return SystemTheme.statStrength
        case .creator: return SystemTheme.primaryPurple
        }
    }

    var defaultQuests: [DailyQuest] {
        switch self {
        case .scholar:
            return [
                DailyQuest(
                    title: "Read 1 Page",
                    description: "A single page. Knowledge compounds.",
                    difficulty: .trivial,
                    targetStats: [.intelligence],
                    trackingType: .manual,
                    targetValue: 1,
                    unit: "page"
                ),
                DailyQuest(
                    title: "1 Minute Focus",
                    description: "Practice stillness of mind.",
                    difficulty: .trivial,
                    targetStats: [.spirit],
                    trackingType: .manual,
                    targetValue: 1,
                    unit: "minute"
                ),
                DailyQuest(
                    title: "Learn Something New",
                    description: "Expand your knowledge today.",
                    difficulty: .easy,
                    targetStats: [.intelligence],
                    trackingType: .manual,
                    targetValue: 1,
                    unit: "thing"
                ),
                DailyQuest(
                    title: "Drink Water",
                    description: "Hydrate your vessel.",
                    difficulty: .trivial,
                    targetStats: [.vitality],
                    trackingType: .manual,
                    targetValue: 8,
                    unit: "glasses"
                )
            ]

        case .athlete:
            return [
                DailyQuest(
                    title: "1 Pushup",
                    description: "Just one. That's all the System asks.",
                    difficulty: .trivial,
                    targetStats: [.strength],
                    trackingType: .manual,
                    targetValue: 1,
                    unit: "pushup"
                ),
                DailyQuest(
                    title: "1 Minute Stretch",
                    description: "Flexibility is freedom.",
                    difficulty: .trivial,
                    targetStats: [.agility],
                    trackingType: .manual,
                    targetValue: 1,
                    unit: "minute"
                ),
                DailyQuest(
                    title: "Move Your Body",
                    description: "Any exercise counts.",
                    difficulty: .easy,
                    targetStats: [.strength, .vitality],
                    trackingType: .manual,
                    targetValue: 10,
                    unit: "minutes"
                ),
                DailyQuest(
                    title: "Sleep 8 Hours",
                    description: "Rest is not weakness. It is regeneration.",
                    difficulty: .normal,
                    targetStats: [.vitality],
                    trackingType: .manual,
                    targetValue: 8,
                    unit: "hours"
                )
            ]

        case .creator:
            return [
                DailyQuest(
                    title: "Create Something",
                    description: "Anything. Just create.",
                    difficulty: .easy,
                    targetStats: [.intelligence, .willpower],
                    trackingType: .manual,
                    targetValue: 1,
                    unit: "thing"
                ),
                DailyQuest(
                    title: "Deep Work Block",
                    description: "15 minutes of focused creation.",
                    difficulty: .normal,
                    targetStats: [.willpower, .intelligence],
                    trackingType: .manual,
                    targetValue: 15,
                    unit: "minutes"
                ),
                DailyQuest(
                    title: "Review Progress",
                    description: "Reflect on what you've built.",
                    difficulty: .trivial,
                    targetStats: [.spirit],
                    trackingType: .manual,
                    targetValue: 1,
                    unit: "review"
                ),
                DailyQuest(
                    title: "Drink Water",
                    description: "Hydrate your vessel.",
                    difficulty: .trivial,
                    targetStats: [.vitality],
                    trackingType: .manual,
                    targetValue: 8,
                    unit: "glasses"
                )
            ]
        }
    }
}

// MARK: - Awakening Phase

/// "You are qualified to be a Player. Will you accept?"
struct AwakeningPhaseView: View {
    let onAccept: () -> Void

    @State private var showContent = false
    @State private var showButton = false
    @State private var glowIntensity: Double = 0.5

    var body: some View {
        VStack(spacing: 40) {
            // System notification box
            if showContent {
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

                    Text("Will you accept?")
                        .font(SystemTypography.systemMessage)
                        .foregroundStyle(SystemTheme.textSecondary)
                }
                .padding(32)
                .background(SystemTheme.backgroundTertiary.opacity(0.95))
                .clipShape(RoundedRectangle(cornerRadius: SystemRadius.large))
                .overlay(
                    RoundedRectangle(cornerRadius: SystemRadius.large)
                        .stroke(SystemTheme.primaryBlue.opacity(glowIntensity), lineWidth: 2)
                )
                .glow(color: SystemTheme.primaryBlue.opacity(0.3), radius: 20)
                .transition(.scale.combined(with: .opacity))
            }

            // Accept button
            if showButton {
                Button(action: onAccept) {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("ACCEPT")
                            .font(SystemTypography.mono(16, weight: .bold))
                    }
                    .foregroundStyle(SystemTheme.backgroundPrimary)
                    .padding(.horizontal, 48)
                    .padding(.vertical, 16)
                    .background(SystemTheme.primaryBlue)
                    .clipShape(Capsule())
                    .glow(color: SystemTheme.primaryBlue, radius: 10)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            // Staggered animations
            withAnimation(.easeOut(duration: 0.8).delay(0.5)) {
                showContent = true
            }
            withAnimation(.easeOut(duration: 0.5).delay(1.5)) {
                showButton = true
            }
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true).delay(0.5)) {
                glowIntensity = 1.0
            }
        }
    }
}

// MARK: - Name Entry Phase

struct NameEntryPhaseView: View {
    @Binding var name: String
    let onContinue: () -> Void

    @State private var showContent = false
    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        VStack(spacing: 32) {
            if showContent {
                VStack(spacing: 24) {
                    Text("[SYSTEM]")
                        .font(SystemTypography.mono(14, weight: .bold))
                        .foregroundStyle(SystemTheme.primaryBlue)

                    Text("Enter your name, Hunter.")
                        .font(SystemTypography.titleSmall)
                        .foregroundStyle(SystemTheme.textPrimary)

                    // Name input field
                    VStack(spacing: 8) {
                        TextField("", text: $name, prompt: Text("Your name...").foregroundStyle(SystemTheme.textTertiary))
                            .font(SystemTypography.mono(20, weight: .semibold))
                            .foregroundStyle(SystemTheme.textPrimary)
                            .multilineTextAlignment(.center)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .focused($isNameFieldFocused)
                            .padding()
                            .background(SystemTheme.backgroundSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: SystemRadius.medium))
                            .overlay(
                                RoundedRectangle(cornerRadius: SystemRadius.medium)
                                    .stroke(SystemTheme.primaryBlue.opacity(0.5), lineWidth: 1)
                            )

                        Text("This name will be displayed on your status window.")
                            .font(SystemTypography.caption)
                            .foregroundStyle(SystemTheme.textTertiary)
                    }
                }
                .padding(32)
                .systemCard()
                .transition(.scale.combined(with: .opacity))

                // Continue button
                Button(action: onContinue) {
                    HStack(spacing: 12) {
                        Text("CONTINUE")
                            .font(SystemTypography.mono(16, weight: .bold))
                        Image(systemName: "arrow.right")
                    }
                    .foregroundStyle(name.isEmpty ? SystemTheme.textTertiary : SystemTheme.backgroundPrimary)
                    .padding(.horizontal, 48)
                    .padding(.vertical, 16)
                    .background(name.isEmpty ? SystemTheme.backgroundTertiary : SystemTheme.primaryBlue)
                    .clipShape(Capsule())
                }
                .disabled(name.isEmpty)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                showContent = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                isNameFieldFocused = true
            }
        }
    }
}

// MARK: - Origin Story Phase

struct OriginStoryPhaseView: View {
    @Binding var originStory: String
    let onContinue: () -> Void

    @State private var showContent = false
    @FocusState private var isTextFieldFocused: Bool

    private let placeholders = [
        "I want to defeat the Dragon of Lethargy...",
        "I will conquer the Mountain of Procrastination...",
        "I seek to master the Art of Focus...",
        "My enemy is the Shadow of Doubt..."
    ]

    var body: some View {
        VStack(spacing: 32) {
            if showContent {
                VStack(spacing: 24) {
                    Text("[SYSTEM]")
                        .font(SystemTypography.mono(14, weight: .bold))
                        .foregroundStyle(SystemTheme.primaryBlue)

                    VStack(spacing: 8) {
                        Text("What is your")
                            .font(SystemTypography.body)
                            .foregroundStyle(SystemTheme.textSecondary)

                        Text("ORIGIN STORY?")
                            .font(SystemTypography.titleMedium)
                            .foregroundStyle(SystemTheme.primaryPurple)
                            .glow(color: SystemTheme.primaryPurple, radius: 8)
                    }

                    Text("Why do you seek power? What dragon do you wish to slay?")
                        .font(SystemTypography.bodySmall)
                        .foregroundStyle(SystemTheme.textSecondary)
                        .multilineTextAlignment(.center)

                    // Origin story input
                    TextEditor(text: $originStory)
                        .font(SystemTypography.body)
                        .foregroundStyle(SystemTheme.textPrimary)
                        .scrollContentBackground(.hidden)
                        .focused($isTextFieldFocused)
                        .frame(minHeight: 120)
                        .padding()
                        .background(SystemTheme.backgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: SystemRadius.medium))
                        .overlay(
                            RoundedRectangle(cornerRadius: SystemRadius.medium)
                                .stroke(SystemTheme.primaryPurple.opacity(0.5), lineWidth: 1)
                        )
                        .overlay(
                            Group {
                                if originStory.isEmpty {
                                    Text(placeholders.randomElement() ?? "Your reason for becoming stronger...")
                                        .font(SystemTypography.body)
                                        .foregroundStyle(SystemTheme.textTertiary)
                                        .padding()
                                        .allowsHitTesting(false)
                                }
                            },
                            alignment: .topLeading
                        )
                }
                .padding(32)
                .systemCard()
                .transition(.scale.combined(with: .opacity))

                // Continue button
                Button(action: onContinue) {
                    HStack(spacing: 12) {
                        Text("BEGIN JOURNEY")
                            .font(SystemTypography.mono(16, weight: .bold))
                        Image(systemName: "arrow.right")
                    }
                    .foregroundStyle(SystemTheme.backgroundPrimary)
                    .padding(.horizontal, 48)
                    .padding(.vertical, 16)
                    .background(SystemTheme.primaryPurple)
                    .clipShape(Capsule())
                    .glow(color: SystemTheme.primaryPurple, radius: 8)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                showContent = true
            }
        }
    }
}

// MARK: - Initial Stats Phase

struct InitialStatsPhaseView: View {
    let onContinue: () -> Void

    @State private var showContent = false
    @State private var showStats = false
    @State private var statsAnimated = false

    private let initialStats: [Stat] = StatType.allCases.map { Stat(type: $0, baseValue: 10) }

    var body: some View {
        VStack(spacing: 32) {
            if showContent {
                VStack(spacing: 24) {
                    Text("[SYSTEM]")
                        .font(SystemTypography.mono(14, weight: .bold))
                        .foregroundStyle(SystemTheme.primaryBlue)

                    Text("Initial Status Assigned")
                        .font(SystemTypography.titleSmall)
                        .foregroundStyle(SystemTheme.textPrimary)

                    if showStats {
                        RadarChartView(stats: initialStats, animated: true)
                            .frame(width: 250, height: 250)

                        Text("All stats start at 10.\nYour journey will shape your power.")
                            .font(SystemTypography.caption)
                            .foregroundStyle(SystemTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(32)
                .systemCard()
                .transition(.scale.combined(with: .opacity))

                if statsAnimated {
                    Button(action: onContinue) {
                        HStack(spacing: 12) {
                            Image(systemName: "play.fill")
                            Text("ENTER THE SYSTEM")
                                .font(SystemTypography.mono(16, weight: .bold))
                        }
                        .foregroundStyle(SystemTheme.backgroundPrimary)
                        .padding(.horizontal, 48)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [SystemTheme.primaryBlue, SystemTheme.primaryPurple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .glow(color: SystemTheme.primaryBlue, radius: 10)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                showContent = true
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.5)) {
                showStats = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeOut(duration: 0.5)) {
                    statsAnimated = true
                }
            }
        }
    }
}

// MARK: - Class Selection Phase

struct ClassSelectionPhaseView: View {
    @Binding var selectedClass: PlayerClass
    let onContinue: () -> Void

    @State private var showContent = false

    var body: some View {
        VStack(spacing: 32) {
            if showContent {
                VStack(spacing: 24) {
                    Text("[SYSTEM]")
                        .font(SystemTypography.mono(14, weight: .bold))
                        .foregroundStyle(SystemTheme.primaryBlue)

                    VStack(spacing: 8) {
                        Text("Choose your")
                            .font(SystemTypography.body)
                            .foregroundStyle(SystemTheme.textSecondary)

                        Text("PATH")
                            .font(SystemTypography.titleMedium)
                            .foregroundStyle(SystemTheme.primaryBlue)
                            .glow(color: SystemTheme.primaryBlue, radius: 8)
                    }

                    Text("Your path determines your initial quests and focus areas.")
                        .font(SystemTypography.caption)
                        .foregroundStyle(SystemTheme.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)
                .transition(.opacity)

                // Class options
                VStack(spacing: 16) {
                    ForEach(PlayerClass.allCases, id: \.self) { playerClass in
                        ClassOptionCard(
                            playerClass: playerClass,
                            isSelected: selectedClass == playerClass,
                            onSelect: { selectedClass = playerClass }
                        )
                    }
                }
                .padding(.horizontal)
                .transition(.scale.combined(with: .opacity))

                // Continue button
                Button(action: onContinue) {
                    HStack(spacing: 12) {
                        Text("CHOOSE \(selectedClass.rawValue.uppercased())")
                            .font(SystemTypography.mono(14, weight: .bold))
                        Image(systemName: "arrow.right")
                    }
                    .foregroundStyle(SystemTheme.backgroundPrimary)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 14)
                    .background(selectedClass.color)
                    .clipShape(Capsule())
                    .glow(color: selectedClass.color, radius: 8)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                showContent = true
            }
        }
    }
}

struct ClassOptionCard: View {
    let playerClass: PlayerClass
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(playerClass.color.opacity(0.2))
                        .frame(width: 50, height: 50)

                    Image(systemName: playerClass.icon)
                        .font(.system(size: 24))
                        .foregroundStyle(playerClass.color)
                }

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(playerClass.rawValue)
                        .font(SystemTypography.headline)
                        .foregroundStyle(SystemTheme.textPrimary)

                    Text(playerClass.description)
                        .font(SystemTypography.captionSmall)
                        .foregroundStyle(SystemTheme.textSecondary)
                        .lineLimit(2)

                    // Primary stats
                    HStack(spacing: 8) {
                        ForEach(playerClass.primaryStats, id: \.self) { stat in
                            Text(stat.rawValue)
                                .font(SystemTypography.mono(10, weight: .semibold))
                                .foregroundStyle(stat.color)
                        }
                    }
                }

                Spacer()

                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(isSelected ? playerClass.color : SystemTheme.textTertiary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: SystemRadius.medium)
                    .fill(SystemTheme.backgroundTertiary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SystemRadius.medium)
                    .stroke(isSelected ? playerClass.color : Color.clear, lineWidth: 2)
            )
        }
    }
}

// MARK: - Setup Quests Phase (Neural Links)

struct SetupQuestsPhaseView: View {
    let onContinue: () -> Void

    @StateObject private var permissionManager = PermissionManager.shared
    @State private var showContent = false
    @State private var completedLinks: Set<NeuralLinkType> = []

    var body: some View {
        VStack(spacing: 32) {
            if showContent {
                VStack(spacing: 24) {
                    Text("[SYSTEM]")
                        .font(SystemTypography.mono(14, weight: .bold))
                        .foregroundStyle(SystemTheme.primaryBlue)

                    VStack(spacing: 8) {
                        Text("Establish")
                            .font(SystemTypography.body)
                            .foregroundStyle(SystemTheme.textSecondary)

                        Text("NEURAL LINKS")
                            .font(SystemTypography.titleMedium)
                            .foregroundStyle(SystemTheme.primaryPurple)
                            .glow(color: SystemTheme.primaryPurple, radius: 8)
                    }

                    Text("Connect GAMELIFE to your device for automatic tracking. These are optional but enhance your experience.")
                        .font(SystemTypography.caption)
                        .foregroundStyle(SystemTheme.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)
                .transition(.opacity)

                // Neural Link options
                VStack(spacing: 12) {
                    ForEach(NeuralLinkType.betaAvailableCases) { linkType in
                        SetupLinkRow(
                            type: linkType,
                            isConnected: permissionManager.isEnabled(for: linkType),
                            onConnect: { connectLink(linkType) }
                        )
                    }
                }
                .padding(.horizontal)
                .transition(.scale.combined(with: .opacity))

                // Skip/Continue button
                VStack(spacing: 12) {
                    Button(action: onContinue) {
                        HStack(spacing: 12) {
                            Image(systemName: "play.fill")
                            Text("ENTER THE SYSTEM")
                                .font(SystemTypography.mono(14, weight: .bold))
                        }
                        .foregroundStyle(SystemTheme.backgroundPrimary)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [SystemTheme.primaryBlue, SystemTheme.primaryPurple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .glow(color: SystemTheme.primaryBlue, radius: 8)
                    }

                    Text("You can set these up later in Settings")
                        .font(SystemTypography.captionSmall)
                        .foregroundStyle(SystemTheme.textTertiary)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                showContent = true
            }
        }
    }

    private func connectLink(_ type: NeuralLinkType) {
        Task {
            do {
                switch type {
                case .vitalSigns:
                    try await permissionManager.requestHealthKit()
                case .mindActivity:
                    try await permissionManager.requestScreenTime()
                case .worldPosition:
                    permissionManager.requestLocation()
                    try await Task.sleep(nanoseconds: 1_200_000_000)
                    permissionManager.checkLocationStatus()
                case .systemMessages:
                    try await permissionManager.requestNotifications()
                }

                if permissionManager.isEnabled(for: type) {
                    completedLinks.insert(type)
                }
            } catch {
                // Permission denied - that's okay, it's optional
            }
        }
    }
}

struct SetupLinkRow: View {
    let type: NeuralLinkType
    let isConnected: Bool
    let onConnect: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(type.color.opacity(0.2))
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

            // Connect button or status
            if isConnected {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Linked")
                }
                .font(SystemTypography.mono(12, weight: .semibold))
                .foregroundStyle(SystemTheme.successGreen)
            } else {
                Button(action: onConnect) {
                    Text("LINK")
                        .font(SystemTypography.mono(12, weight: .bold))
                        .foregroundStyle(SystemTheme.backgroundPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(type.color)
                        .clipShape(Capsule())
                }
            }
        }
        .padding()
        .background(SystemTheme.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: SystemRadius.medium))
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
        case .vitalSigns: return "Track steps, workouts, sleep"
        case .mindActivity: return "Track app usage automatically"
        case .worldPosition: return "Auto-complete location quests"
        case .systemMessages: return "Get quest reminders"
        }
    }
}

// MARK: - Particle Field View

/// Animated background particles for atmosphere
struct ParticleFieldView: View {
    @State private var particles: [Particle] = []

    struct Particle: Identifiable {
        let id = UUID()
        var x: CGFloat
        var y: CGFloat
        var size: CGFloat
        var opacity: Double
        var speed: Double
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(particles) { particle in
                    Circle()
                        .fill(SystemTheme.primaryBlue)
                        .frame(width: particle.size, height: particle.size)
                        .position(x: particle.x, y: particle.y)
                        .opacity(particle.opacity)
                }
            }
            .onAppear {
                // Generate initial particles
                for _ in 0..<50 {
                    particles.append(Particle(
                        x: CGFloat.random(in: 0...geometry.size.width),
                        y: CGFloat.random(in: 0...geometry.size.height),
                        size: CGFloat.random(in: 2...6),
                        opacity: Double.random(in: 0.1...0.5),
                        speed: Double.random(in: 0.5...2)
                    ))
                }

                // Animate particles
                Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                    for i in particles.indices {
                        particles[i].y -= CGFloat(particles[i].speed)
                        if particles[i].y < -10 {
                            particles[i].y = geometry.size.height + 10
                            particles[i].x = CGFloat.random(in: 0...geometry.size.width)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Onboarding Flow") {
    OnboardingView(isOnboardingComplete: .constant(false))
}

#Preview("Awakening Phase") {
    ZStack {
        SystemTheme.backgroundPrimary.ignoresSafeArea()
        AwakeningPhaseView(onAccept: {})
    }
}
