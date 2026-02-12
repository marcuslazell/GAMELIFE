//
//  SystemTheme.swift
//  GAMELIFE
//
//  [SYSTEM]: Visual identity initialized.
//  Dark Mode exclusive. The shadows are your canvas.
//

import SwiftUI
import UIKit

// MARK: - System Theme

/// The visual identity of the System - Dark, sleek, powerful
struct SystemTheme {

    private static func adaptiveColor(light: String, dark: String) -> Color {
        Color(
            UIColor { traits in
                UIColor(
                    hex: traits.userInterfaceStyle == .dark ? dark : light
                )
            }
        )
    }

    // MARK: - Primary Colors (Solo Leveling Inspired)

    /// Primary neon blue - The System's signature
    static let primaryBlue = Color(hex: "4CC9F0")

    /// Primary purple - Power and mystery
    static let primaryPurple = Color(hex: "7B2CBF")

    /// Secondary purple - Lighter accent
    static let secondaryPurple = Color(hex: "9D4EDD")

    /// Accent cyan - Highlights and glows
    static let accentCyan = Color(hex: "00F5D4")

    /// Warning orange - Penalties and alerts
    static let warningOrange = Color(hex: "FF6B35")

    /// Critical red - Damage and failures
    static let criticalRed = Color(hex: "EF233C")

    /// Success green - Completions and victories
    static let successGreen = Color(hex: "06D6A0")

    /// Gold - Currency and legendary items
    static let goldColor = Color(hex: "FFD700")

    // MARK: - Background Colors

    /// Primary background - Deep void black
    static let backgroundPrimary = adaptiveColor(light: "F4F6FA", dark: "0A0A0F")

    /// Secondary background - Slightly lighter
    static let backgroundSecondary = adaptiveColor(light: "FFFFFF", dark: "12121A")

    /// Tertiary background - Card surfaces
    static let backgroundTertiary = adaptiveColor(light: "E9EEF7", dark: "1A1A2E")

    /// Elevated surface - Modals and overlays
    static let backgroundElevated = adaptiveColor(light: "FFFFFF", dark: "252538")

    // MARK: - Text Colors

    /// Primary text - High contrast
    static let textPrimary = adaptiveColor(light: "111420", dark: "FFFFFF")

    /// Secondary text - Muted
    static let textSecondary = adaptiveColor(light: "495066", dark: "A0A0B0")

    /// Tertiary text - Very muted
    static let textTertiary = adaptiveColor(light: "7A8198", dark: "606070")

    /// System text - Blue tinted
    static let textSystem = primaryBlue

    // MARK: - Stat Colors

    static let statStrength = Color(hex: "EF233C")      // Red - Power
    static let statIntelligence = Color(hex: "4CC9F0")  // Blue - Mind
    static let statAgility = Color(hex: "06D6A0")       // Green - Speed
    static let statVitality = Color(hex: "FF6B35")      // Orange - Life
    static let statWillpower = Color(hex: "9D4EDD")     // Purple - Will
    static let statSpirit = Color(hex: "FFD700")        // Gold - Soul

    // MARK: - Gradients

    /// Primary gradient - Blue to Purple
    static let primaryGradient = LinearGradient(
        colors: [primaryBlue, primaryPurple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// System glow gradient
    static let systemGlow = RadialGradient(
        colors: [primaryBlue.opacity(0.3), Color.clear],
        center: .center,
        startRadius: 0,
        endRadius: 150
    )

    /// XP bar gradient
    static let xpGradient = LinearGradient(
        colors: [primaryBlue, accentCyan],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// HP bar gradient (for bosses)
    static let hpGradient = LinearGradient(
        colors: [criticalRed, warningOrange],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Gold gradient
    static let goldGradient = LinearGradient(
        colors: [Color(hex: "FFD700"), Color(hex: "FFA500")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Shadows

    static let glowShadow = Color.blue.opacity(0.5)
    static let cardShadow = Color.black.opacity(0.3)

    // MARK: - Border Colors

    static let borderPrimary = primaryBlue.opacity(0.3)
    static let borderSecondary = adaptiveColor(light: "D7DEEA", dark: "FFFFFF").opacity(0.25)

    // MARK: - Animation Durations

    static let animationFast: Double = 0.2
    static let animationNormal: Double = 0.3
    static let animationSlow: Double = 0.5
    static let animationVeryLong: Double = 1.0
}

// MARK: - Color Extension for Hex Support

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 3:
            (r, g, b) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (1, 1, 1)
        }

        self.init(
            red: CGFloat(r) / 255.0,
            green: CGFloat(g) / 255.0,
            blue: CGFloat(b) / 255.0,
            alpha: 1.0
        )
    }
}

// MARK: - Typography

/// System fonts - Monospace for stats, Sans-serif for content
struct SystemTypography {

    // MARK: - Monospace (Stats & Numbers)

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static let statLarge = mono(48, weight: .bold)
    static let statMedium = mono(32, weight: .bold)
    static let statSmall = mono(24, weight: .semibold)
    static let statTiny = mono(14, weight: .medium)

    static let timer = mono(64, weight: .ultraLight)
    static let timerSmall = mono(32, weight: .light)

    static let xpCounter = mono(18, weight: .bold)
    static let goldCounter = mono(16, weight: .semibold)

    // MARK: - Sans-Serif (Content)

    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static let titleLarge = sans(34, weight: .bold)
    static let titleMedium = sans(28, weight: .bold)
    static let titleSmall = sans(22, weight: .semibold)

    static let headline = sans(17, weight: .semibold)
    static let body = sans(17, weight: .regular)
    static let bodySmall = sans(15, weight: .regular)

    static let caption = sans(13, weight: .regular)
    static let captionSmall = sans(11, weight: .regular)

    // MARK: - System Messages

    static let systemMessage = mono(14, weight: .medium)
    static let systemTitle = mono(18, weight: .bold)
    static let systemAlert = mono(16, weight: .semibold)
}

// MARK: - Spacing

struct SystemSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

// MARK: - Corner Radius

struct SystemRadius {
    static let small: CGFloat = 4
    static let medium: CGFloat = 8
    static let large: CGFloat = 12
    static let xlarge: CGFloat = 16
    static let full: CGFloat = 999
}

// MARK: - View Modifiers

/// Glow effect modifier
struct GlowModifier: ViewModifier {
    let color: Color
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .shadow(color: color, radius: radius / 2, x: 0, y: 0)
            .shadow(color: color, radius: radius, x: 0, y: 0)
    }
}

/// System card style modifier
struct SystemCardModifier: ViewModifier {
    let isElevated: Bool

    func body(content: Content) -> some View {
        content
            .background(isElevated ? SystemTheme.backgroundElevated : SystemTheme.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: SystemRadius.large))
            .overlay(
                RoundedRectangle(cornerRadius: SystemRadius.large)
                    .stroke(SystemTheme.borderPrimary, lineWidth: 1)
            )
    }
}

/// Holographic border effect
struct HolographicBorderModifier: ViewModifier {
    @State private var animationPhase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: SystemRadius.large)
                    .stroke(
                        AngularGradient(
                            colors: [
                                SystemTheme.primaryBlue,
                                SystemTheme.primaryPurple,
                                SystemTheme.accentCyan,
                                SystemTheme.primaryBlue
                            ],
                            center: .center,
                            startAngle: .degrees(animationPhase),
                            endAngle: .degrees(animationPhase + 360)
                        ),
                        lineWidth: 2
                    )
            )
            .onAppear {
                withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                    animationPhase = 360
                }
            }
    }
}

// MARK: - View Extensions

extension View {

    /// Apply a glow effect
    func glow(color: Color = SystemTheme.primaryBlue, radius: CGFloat = 10) -> some View {
        modifier(GlowModifier(color: color, radius: radius))
    }

    /// Apply system card styling
    func systemCard(elevated: Bool = false) -> some View {
        modifier(SystemCardModifier(isElevated: elevated))
    }

    /// Apply holographic animated border
    func holographicBorder() -> some View {
        modifier(HolographicBorderModifier())
    }

    /// Apply system background
    func systemBackground() -> some View {
        self.background(SystemTheme.backgroundPrimary)
    }
}

// MARK: - Preview Support

#Preview("System Theme Colors") {
    ScrollView {
        VStack(spacing: 20) {
            Group {
                Text("Primary Colors")
                    .font(SystemTypography.headline)
                    .foregroundStyle(SystemTheme.textPrimary)

                HStack(spacing: 10) {
                    colorSwatch("Blue", SystemTheme.primaryBlue)
                    colorSwatch("Purple", SystemTheme.primaryPurple)
                    colorSwatch("Cyan", SystemTheme.accentCyan)
                }
            }

            Group {
                Text("Stat Colors")
                    .font(SystemTypography.headline)
                    .foregroundStyle(SystemTheme.textPrimary)

                HStack(spacing: 10) {
                    colorSwatch("STR", SystemTheme.statStrength)
                    colorSwatch("INT", SystemTheme.statIntelligence)
                    colorSwatch("AGI", SystemTheme.statAgility)
                }
                HStack(spacing: 10) {
                    colorSwatch("VIT", SystemTheme.statVitality)
                    colorSwatch("WIL", SystemTheme.statWillpower)
                    colorSwatch("SPI", SystemTheme.statSpirit)
                }
            }

            Group {
                Text("Typography")
                    .font(SystemTypography.headline)
                    .foregroundStyle(SystemTheme.textPrimary)

                Text("99")
                    .font(SystemTypography.statLarge)
                    .foregroundStyle(SystemTheme.primaryBlue)

                Text("SYSTEM MESSAGE")
                    .font(SystemTypography.systemMessage)
                    .foregroundStyle(SystemTheme.textSystem)
            }
        }
        .padding()
    }
    .background(SystemTheme.backgroundPrimary)
}

@ViewBuilder
private func colorSwatch(_ name: String, _ color: Color) -> some View {
    VStack {
        RoundedRectangle(cornerRadius: 8)
            .fill(color)
            .frame(width: 60, height: 60)
            .glow(color: color, radius: 5)

        Text(name)
            .font(SystemTypography.captionSmall)
            .foregroundStyle(SystemTheme.textSecondary)
    }
}
