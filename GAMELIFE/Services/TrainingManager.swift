//
//  TrainingManager.swift
//  GAMELIFE
//
//  [SYSTEM]: Focus protocol initialized.
//  Enter the training grounds, Hunter.
//

import SwiftUI
import Combine

// MARK: - Training Manager

/// Manages focus/training sessions (formerly "Dungeon")
/// Handles timer, focus mode, and session rewards
@MainActor
class TrainingManager: ObservableObject {

    // MARK: - Singleton

    static let shared = TrainingManager()

    // MARK: - Published Properties

    @Published var isActive: Bool = false
    @Published var focusModeEnabled: Bool = false
    @Published var elapsedSeconds: Int = 0
    @Published var totalSeconds: Int = 0
    @Published var sessionTitle: String = "Training Session"

    // MARK: - Private Properties

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed Properties

    var remainingSeconds: Int {
        max(0, totalSeconds - elapsedSeconds)
    }

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(elapsedSeconds) / Double(totalSeconds)
    }

    var isComplete: Bool {
        elapsedSeconds >= totalSeconds && totalSeconds > 0
    }

    var formattedTimeRemaining: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var formattedElapsedTime: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var durationMinutes: Int {
        totalSeconds / 60
    }

    // XP reward based on duration
    var xpReward: Int {
        // Base: 10 XP per 15 minutes
        let baseXP = (durationMinutes / 15) * 10
        return max(10, baseXP)
    }

    var goldReward: Int {
        // Base: 5 gold per 15 minutes
        let baseGold = (durationMinutes / 15) * 5
        return max(5, baseGold)
    }

    // MARK: - Initialization

    private init() {}

    // MARK: - Session Control

    /// Start a new training session
    /// - Parameters:
    ///   - minutes: Duration in minutes
    ///   - title: Optional custom session title
    func startSession(minutes: Int, title: String = "Training Session") {
        guard !isActive else { return }

        // [SYSTEM]: Training session initiated
        sessionTitle = title
        totalSeconds = minutes * 60
        elapsedSeconds = 0
        isActive = true
        focusModeEnabled = true

        // Start the timer
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }

        // [SYSTEM]: Suggest enabling Do Not Disturb
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            SystemMessageHelper.showInfo(
                "Focus Mode Active",
                "Activate Do Not Disturb for maximum XP gain."
            )
        }
    }

    /// Tick the timer forward by one second
    private func tick() {
        guard isActive else { return }

        elapsedSeconds += 1

        if isComplete {
            complete()
        }
    }

    /// Complete the session successfully
    func complete() {
        guard isActive else { return }

        // Stop timer
        timer?.invalidate()
        timer = nil

        // Award rewards
        let xp = xpReward
        let gold = goldReward

        // Update game state
        let engine = GameEngine.shared
        _ = engine.awardXP(xp)
        engine.player.gold += gold
        engine.player.dungeonsClearedCount += 1
        engine.awardStatXP(.intelligence, amount: 15)
        engine.awardStatXP(.willpower, amount: 15)
        engine.recordExternalActivity(
            type: .questCompleted,
            title: sessionTitle,
            detail: "+\(xp) XP • +\(gold) Gold"
        )

        // Show completion message
        SystemMessageHelper.showInfo(
            "Training Complete",
            "+\(xp) XP, +\(gold) Gold earned."
        )

        // Reset state
        isActive = false
        focusModeEnabled = false
    }

    /// Abandon the session early (applies penalty)
    func abandon(
        reason: PenaltyReason = .dungeonFailed,
        warningMessage: String = "Training session abandoned. A penalty has been applied."
    ) {
        guard isActive else { return }

        // Stop timer
        timer?.invalidate()
        timer = nil

        // Apply penalty
        let engine = GameEngine.shared
        engine.applyPenalty(reason: reason)
        engine.save()

        // Show warning
        SystemMessageHelper.showWarning(warningMessage)

        // Reset state
        isActive = false
        focusModeEnabled = false
        elapsedSeconds = 0
        totalSeconds = 0
    }

    /// Fail the current training session when the app is backgrounded.
    func failForAppExit() {
        abandon(
            reason: .dungeonFailed,
            warningMessage: "Training failed because you left the app before the timer ended."
        )
    }

    /// Toggle focus mode (screen dimming)
    func toggleFocusMode() {
        focusModeEnabled.toggle()
    }

    /// Pause the session (for emergencies)
    func pause() {
        timer?.invalidate()
        timer = nil
    }

    /// Resume a paused session
    func resume() {
        guard isActive && timer == nil else { return }

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        timer?.invalidate()
        timer = nil
        isActive = false
        focusModeEnabled = false
    }
}

// MARK: - Training Difficulty

/// Training session difficulty levels
enum TrainingDifficulty: String, CaseIterable {
    case quick = "Quick"       // 15 min
    case standard = "Standard" // 30 min
    case intense = "Intense"   // 45 min
    case marathon = "Marathon" // 60 min

    var minutes: Int {
        switch self {
        case .quick: return 15
        case .standard: return 30
        case .intense: return 45
        case .marathon: return 60
        }
    }

    var xpMultiplier: Double {
        switch self {
        case .quick: return 1.0
        case .standard: return 1.2
        case .intense: return 1.5
        case .marathon: return 2.0
        }
    }

    var color: Color {
        switch self {
        case .quick: return SystemTheme.successGreen
        case .standard: return SystemTheme.primaryBlue
        case .intense: return SystemTheme.primaryPurple
        case .marathon: return SystemTheme.goldColor
        }
    }
}
