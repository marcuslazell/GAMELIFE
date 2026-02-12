//
//  SystemMessageBanner.swift
//  GAMELIFE
//
//  [SYSTEM]: Communication relay initialized.
//  In-app notifications flow through this conduit.
//

import SwiftUI

// MARK: - System Message

/// A system notification displayed as an in-app banner
struct SystemMessage: Identifiable, Equatable {
    let id = UUID()
    let type: MessageType
    let title: String
    let message: String
    let duration: TimeInterval

    init(type: MessageType, title: String, message: String, duration: TimeInterval = 4.0) {
        self.type = type
        self.title = title
        self.message = message
        self.duration = duration
    }

    // MARK: - Message Types

    enum MessageType: String {
        case info = "Info"
        case success = "Success"
        case warning = "Warning"
        case critical = "Critical"
        case levelUp = "Level Up"
        case questComplete = "Quest Complete"

        var color: Color {
            switch self {
            case .info: return SystemTheme.primaryBlue
            case .success: return SystemTheme.successGreen
            case .warning: return SystemTheme.warningOrange
            case .critical: return SystemTheme.criticalRed
            case .levelUp: return SystemTheme.goldColor
            case .questComplete: return SystemTheme.successGreen
            }
        }

        var icon: String {
            switch self {
            case .info: return "diamond.fill"
            case .success: return "checkmark.diamond.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .critical: return "xmark.diamond.fill"
            case .levelUp: return "arrow.up.circle.fill"
            case .questComplete: return "star.fill"
            }
        }
    }

    // MARK: - Static Helpers

    static func questCompleted(title: String, xp: Int, gold: Int) -> SystemMessage {
        SystemMessage(
            type: .questComplete,
            title: "Quest Complete",
            message: "\(title) - +\(xp) XP, +\(gold) Gold"
        )
    }

    static func levelUp(level: Int, rank: String) -> SystemMessage {
        SystemMessage(
            type: .levelUp,
            title: "LEVEL UP!",
            message: "You have reached Level \(level). Rank: \(rank)",
            duration: 6.0
        )
    }

    static func warning(_ message: String) -> SystemMessage {
        SystemMessage(type: .warning, title: "Warning", message: message)
    }

    static func info(_ title: String, _ message: String) -> SystemMessage {
        SystemMessage(type: .info, title: title, message: message)
    }
}

// MARK: - System Message Banner View

/// Holographic banner for in-app notifications
struct SystemMessageBanner: View {

    let message: SystemMessage
    let onDismiss: () -> Void

    @State private var opacity: Double = 0
    @State private var offsetY: CGFloat = -100
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: message.type.icon)
                .font(.system(size: 24))
                .foregroundStyle(message.type.color)
                .glow(color: message.type.color, radius: 8)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text("[SYSTEM] \(message.title)")
                    .font(SystemTypography.systemMessage)
                    .foregroundStyle(message.type.color)

                Text(message.message)
                    .font(SystemTypography.caption)
                    .foregroundStyle(SystemTheme.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            // Dismiss button
            Button {
                dismissBanner()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SystemTheme.textTertiary)
                    .padding(8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: SystemRadius.medium)
                .fill(SystemTheme.backgroundTertiary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SystemRadius.medium)
                .stroke(message.type.color.opacity(0.5), lineWidth: 1)
        )
        .glow(color: message.type.color, radius: 5)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .offset(y: offsetY)
        .opacity(opacity)
        .onAppear {
            // Animate in
            withAnimation(.easeOut(duration: 0.2)) {
                opacity = 1
                offsetY = 0
            }

            // Schedule auto-dismiss
            dismissTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(message.duration * 1_000_000_000))
                if !Task.isCancelled {
                    await MainActor.run {
                        dismissBanner()
                    }
                }
            }
        }
        .onDisappear {
            dismissTask?.cancel()
        }
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.height < -20 {
                        dismissBanner()
                    }
                }
        )
    }

    private func dismissBanner() {
        dismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.25)) {
            opacity = 0
            offsetY = -100
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDismiss()
        }
    }
}

// MARK: - View Extension

extension View {
    /// Displays system messages as banners
    func systemMessage(_ message: Binding<SystemMessage?>) -> some View {
        ZStack(alignment: .top) {
            self

            if let msg = message.wrappedValue {
                SystemMessageBanner(message: msg) {
                    message.wrappedValue = nil
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

// MARK: - System Message Helper

/// Helper class to post system messages from anywhere
class SystemMessageHelper {
    static func show(_ message: SystemMessage) {
        NotificationCenter.default.post(
            name: .showSystemMessage,
            object: message
        )
    }

    static func showQuestComplete(title: String, xp: Int, gold: Int) {
        show(.questCompleted(title: title, xp: xp, gold: gold))
    }

    static func showLevelUp(level: Int, rank: String) {
        show(.levelUp(level: level, rank: rank))
    }

    static func showWarning(_ message: String) {
        show(.warning(message))
    }

    static func showInfo(_ title: String, _ message: String) {
        show(.info(title, message))
    }
}

// MARK: - Preview

#Preview("Info Banner") {
    ZStack {
        SystemTheme.backgroundPrimary.ignoresSafeArea()

        VStack {
            SystemMessageBanner(
                message: .info("Training Complete", "You have completed a 25-minute focus session. +50 XP")
            ) {}

            Spacer()
        }
    }
}

#Preview("Level Up Banner") {
    ZStack {
        SystemTheme.backgroundPrimary.ignoresSafeArea()

        VStack {
            SystemMessageBanner(
                message: .levelUp(level: 25, rank: "C-Rank Hunter")
            ) {}

            Spacer()
        }
    }
}
