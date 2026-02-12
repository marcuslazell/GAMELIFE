//
//  TrainingView.swift
//  GAMELIFE
//
//  [SYSTEM]: Training grounds accessed.
//  Focus is power, Hunter.
//

import SwiftUI

// MARK: - Training View

/// Tab 3: Focus timer for deep work sessions (formerly "Dungeon")
struct TrainingView: View {

    // MARK: - Properties

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var trainingManager = TrainingManager.shared
    @State private var showCustomPicker = false
    @State private var customMinutes: Int = 25

    // Timer presets: 15m, 30m, 45m, 60m
    private let presets: [Int] = [15, 30, 45, 60]

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                SystemTheme.backgroundPrimary
                    .ignoresSafeArea()

                if trainingManager.isActive {
                    // Active training session
                    ActiveTrainingView(manager: trainingManager)
                } else {
                    // Training selection
                    TrainingSelectionView(
                        presets: presets,
                        onSelect: { minutes in
                            trainingManager.startSession(minutes: minutes)
                        },
                        onCustom: {
                            showCustomPicker = true
                        }
                    )
                }

                // Focus mode overlay (90% black dimming)
                if trainingManager.focusModeEnabled && trainingManager.isActive {
                    FocusModeOverlay(manager: trainingManager)
                }
            }
            .navigationTitle("Training")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(SystemTheme.backgroundPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showCustomPicker) {
                CustomDurationPicker(
                    minutes: $customMinutes,
                    onConfirm: {
                        showCustomPicker = false
                        trainingManager.startSession(minutes: customMinutes)
                    }
                )
                .presentationDetents([.height(300)])
                .presentationDragIndicator(.visible)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background && trainingManager.isActive {
                    trainingManager.failForAppExit()
                }
            }
        }
    }
}

// MARK: - Training Selection View

/// Duration selection screen
struct TrainingSelectionView: View {
    let presets: [Int]
    let onSelect: (Int) -> Void
    let onCustom: () -> Void

    var body: some View {
        VStack(spacing: SystemSpacing.xl) {
            Spacer()

            // Header
            VStack(spacing: SystemSpacing.sm) {
                Image(systemName: "timer")
                    .font(.system(size: 48))
                    .foregroundStyle(SystemTheme.primaryPurple)
                    .glow(color: SystemTheme.primaryPurple, radius: 10)

                Text("Select Duration")
                    .font(SystemTypography.titleSmall)
                    .foregroundStyle(SystemTheme.textPrimary)

                Text("\"Enter the realm of deep focus\"")
                    .font(SystemTypography.caption)
                    .foregroundStyle(SystemTheme.textTertiary)
                    .italic()
            }

            // Preset buttons
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: SystemSpacing.md) {
                ForEach(presets, id: \.self) { minutes in
                    TrainingPresetButton(
                        minutes: minutes,
                        onTap: { onSelect(minutes) }
                    )
                }
            }
            .padding(.horizontal, SystemSpacing.lg)

            // Custom button
            Button(action: onCustom) {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                    Text("Custom Duration")
                }
                .font(SystemTypography.mono(14, weight: .semibold))
                .foregroundStyle(SystemTheme.primaryBlue)
                .padding()
                .frame(maxWidth: .infinity)
                .background(SystemTheme.primaryBlue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: SystemRadius.medium))
                .overlay(
                    RoundedRectangle(cornerRadius: SystemRadius.medium)
                        .stroke(SystemTheme.primaryBlue.opacity(0.3), lineWidth: 1)
                )
            }
            .padding(.horizontal, SystemSpacing.lg)

            Spacer()

            // Info text
            VStack(spacing: SystemSpacing.xs) {
                Text("Deep work sessions grant bonus XP and stat increases.")
                    .font(SystemTypography.caption)
                    .foregroundStyle(SystemTheme.textSecondary)

                Text("Focus is power.")
                    .font(SystemTypography.mono(12, weight: .semibold))
                    .foregroundStyle(SystemTheme.primaryPurple)
            }
            .multilineTextAlignment(.center)
            .padding(.bottom, SystemSpacing.xl)
        }
    }
}

// MARK: - Training Preset Button

struct TrainingPresetButton: View {
    let minutes: Int
    let onTap: () -> Void

    private var difficulty: TrainingDifficulty {
        switch minutes {
        case 15: return .quick
        case 30: return .standard
        case 45: return .intense
        case 60: return .marathon
        default: return .standard
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: SystemSpacing.xs) {
                Text("\(minutes)")
                    .font(SystemTypography.statMedium)
                    .foregroundStyle(difficulty.color)

                Text("minutes")
                    .font(SystemTypography.caption)
                    .foregroundStyle(SystemTheme.textSecondary)

                Text(difficulty.rawValue)
                    .font(SystemTypography.captionSmall)
                    .foregroundStyle(difficulty.color.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, SystemSpacing.lg)
            .background(SystemTheme.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: SystemRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: SystemRadius.medium)
                    .stroke(difficulty.color.opacity(0.3), lineWidth: 1)
            )
        }
    }
}

// MARK: - Active Training View

struct ActiveTrainingView: View {
    @ObservedObject var manager: TrainingManager

    @State private var pulseAnimation = false

    var body: some View {
        VStack(spacing: SystemSpacing.xl) {
            Spacer()

            // Session title
            VStack(spacing: SystemSpacing.sm) {
                Text("TRAINING ACTIVE")
                    .font(SystemTypography.mono(14, weight: .bold))
                    .foregroundStyle(SystemTheme.primaryPurple)

                Text(manager.sessionTitle)
                    .font(SystemTypography.titleSmall)
                    .foregroundStyle(SystemTheme.textPrimary)
            }

            // Timer display
            ZStack {
                // Background ring
                Circle()
                    .stroke(SystemTheme.backgroundSecondary, lineWidth: 8)
                    .frame(width: 220, height: 220)

                // Progress ring
                Circle()
                    .trim(from: 0, to: manager.progress)
                    .stroke(
                        LinearGradient(
                            colors: [SystemTheme.primaryBlue, SystemTheme.primaryPurple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 220, height: 220)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: manager.progress)

                // Time display
                VStack(spacing: 4) {
                    Text(manager.formattedTimeRemaining)
                        .font(SystemTypography.timer)
                        .foregroundStyle(SystemTheme.textPrimary)

                    Text("remaining")
                        .font(SystemTypography.caption)
                        .foregroundStyle(SystemTheme.textTertiary)
                }
            }
            .glow(color: SystemTheme.primaryPurple.opacity(pulseAnimation ? 0.5 : 0.2), radius: 20)

            // Reward preview
            HStack(spacing: SystemSpacing.lg) {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(SystemTheme.primaryBlue)
                    Text("+\(manager.xpReward) XP")
                        .font(SystemTypography.mono(14, weight: .semibold))
                        .foregroundStyle(SystemTheme.primaryBlue)
                }

                HStack(spacing: 4) {
                    Image(systemName: "dollarsign.circle.fill")
                        .foregroundStyle(SystemTheme.goldColor)
                    Text("+\(manager.goldReward) Gold")
                        .font(SystemTypography.mono(14, weight: .semibold))
                        .foregroundStyle(SystemTheme.goldColor)
                }
            }

            Spacer()

            // Control buttons
            VStack(spacing: SystemSpacing.md) {
                // Focus Mode Toggle
                Button {
                    manager.toggleFocusMode()
                } label: {
                    HStack {
                        Image(systemName: manager.focusModeEnabled ? "moon.fill" : "moon")
                        Text(manager.focusModeEnabled ? "Exit Focus Mode" : "Enter Focus Mode")
                    }
                    .font(SystemTypography.mono(14, weight: .semibold))
                    .foregroundStyle(SystemTheme.primaryBlue)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(SystemTheme.primaryBlue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: SystemRadius.medium))
                }

                // Abandon button
                Button {
                    manager.abandon()
                } label: {
                    HStack {
                        Image(systemName: "xmark.circle")
                        Text("ABANDON TRAINING")
                    }
                    .font(SystemTypography.mono(14, weight: .semibold))
                    .foregroundStyle(SystemTheme.criticalRed)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(SystemTheme.criticalRed.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: SystemRadius.medium))
                    .overlay(
                        RoundedRectangle(cornerRadius: SystemRadius.medium)
                            .stroke(SystemTheme.criticalRed.opacity(0.3), lineWidth: 1)
                    )
                }

                // Warning text
                Text("Leaving early will apply a penalty.")
                    .font(SystemTypography.captionSmall)
                    .foregroundStyle(SystemTheme.textTertiary)
            }
            .padding(.horizontal, SystemSpacing.lg)
            .padding(.bottom, SystemSpacing.xl)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
        }
    }
}

// MARK: - Focus Mode Overlay

/// 90% black overlay for screen dimming during focus sessions
struct FocusModeOverlay: View {
    @ObservedObject var manager: TrainingManager

    var body: some View {
        ZStack {
            // Dark overlay (90% opacity)
            Color.black.opacity(0.9)
                .ignoresSafeArea()

            VStack(spacing: SystemSpacing.xxl) {
                // Timer
                Text(manager.formattedTimeRemaining)
                    .font(SystemTypography.timer)
                    .foregroundStyle(SystemTheme.primaryBlue)
                    .glow(color: SystemTheme.primaryBlue, radius: 15)

                // Message
                Text("Stay focused, Hunter.")
                    .font(SystemTypography.systemMessage)
                    .foregroundStyle(SystemTheme.textSecondary)

                // Exit button
                Button {
                    manager.toggleFocusMode()
                } label: {
                    Text("Exit Focus Mode")
                        .font(SystemTypography.mono(14, weight: .semibold))
                        .foregroundStyle(SystemTheme.textTertiary)
                        .padding()
                }
            }
        }
        .onAppear {
            // [SYSTEM]: Keep screen awake during focus mode
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
}

// MARK: - Custom Duration Picker

struct CustomDurationPicker: View {
    @Binding var minutes: Int
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: SystemSpacing.lg) {
                Text("Custom Duration")
                    .font(SystemTypography.titleSmall)
                    .foregroundStyle(SystemTheme.textPrimary)

                Picker("Minutes", selection: $minutes) {
                    ForEach(Array(stride(from: 5, through: 120, by: 5)), id: \.self) { min in
                        Text("\(min) minutes").tag(min)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 120)

                Button(action: onConfirm) {
                    Text("Start Training")
                        .font(SystemTypography.mono(16, weight: .bold))
                        .foregroundStyle(SystemTheme.backgroundPrimary)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(SystemTheme.primaryPurple)
                        .clipShape(RoundedRectangle(cornerRadius: SystemRadius.medium))
                }
                .padding(.horizontal)
            }
            .padding()
            .background(SystemTheme.backgroundSecondary)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Selection") {
    TrainingView()
}

#Preview("Active") {
    TrainingView()
        .onAppear {
            TrainingManager.shared.startSession(minutes: 25)
        }
}
