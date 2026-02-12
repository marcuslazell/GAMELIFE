//
//  RadarChartView.swift
//  GAMELIFE
//
//  [SYSTEM]: Status window initialized.
//  Your attributes are now visible.
//

import SwiftUI

// MARK: - Radar Chart View

/// A hexagonal radar chart displaying the six core stats
/// Inspired by Solo Leveling's status windows
struct RadarChartView: View {
    let stats: [Stat]
    let maxValue: Double
    let animated: Bool

    @State private var animationProgress: CGFloat = 0
    @State private var glowOpacity: Double = 0.5

    init(stats: [Stat], maxValue: Double = 100, animated: Bool = true) {
        self.stats = stats
        self.maxValue = maxValue
        self.animated = animated
    }

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let baseRadius = min(geometry.size.width, geometry.size.height) / 2
            let radius = max(20, baseRadius - 36)
            let labelRadius = radius + max(12, min(20, radius * 0.35))

            ZStack {
                // Background grid layers
                ForEach(1...5, id: \.self) { level in
                    RadarGridLayer(
                        center: center,
                        radius: radius * CGFloat(level) / 5,
                        sides: 6,
                        opacity: level == 5 ? 0.4 : 0.15
                    )
                }

                // Axis lines
                RadarAxisLines(center: center, radius: radius, sides: 6)

                // Data polygon (animated)
                RadarDataPolygon(
                    center: center,
                    radius: radius,
                    stats: stats,
                    maxValue: maxValue,
                    progress: animated ? animationProgress : 1.0
                )

                // Stat labels
                RadarStatLabels(
                    center: center,
                    radius: labelRadius,
                    stats: stats
                )

                // Glowing center point
                Circle()
                    .fill(SystemTheme.primaryBlue)
                    .frame(width: 8, height: 8)
                    .position(center)
                    .glow(color: SystemTheme.primaryBlue, radius: 8)

                // Animated glow ring
                Circle()
                    .stroke(SystemTheme.primaryBlue.opacity(glowOpacity * 0.3), lineWidth: 2)
                    .frame(width: max(0, radius * 2 + 20), height: max(0, radius * 2 + 20))
                    .position(center)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .onAppear {
            if animated {
                withAnimation(.easeOut(duration: 1.2)) {
                    animationProgress = 1.0
                }
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    glowOpacity = 1.0
                }
            } else {
                animationProgress = 1.0
            }
        }
    }
}

// MARK: - Radar Grid Layer

/// A single hexagonal grid layer
struct RadarGridLayer: View {
    let center: CGPoint
    let radius: CGFloat
    let sides: Int
    let opacity: Double

    var body: some View {
        Path { path in
            let points = polygonPoints(center: center, radius: radius, sides: sides)
            guard let first = points.first else { return }

            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            path.closeSubpath()
        }
        .stroke(SystemTheme.primaryBlue.opacity(opacity), lineWidth: 1)
    }
}

// MARK: - Radar Axis Lines

/// Lines from center to each vertex
struct RadarAxisLines: View {
    let center: CGPoint
    let radius: CGFloat
    let sides: Int

    var body: some View {
        Path { path in
            let points = polygonPoints(center: center, radius: radius, sides: sides)
            for point in points {
                path.move(to: center)
                path.addLine(to: point)
            }
        }
        .stroke(SystemTheme.primaryBlue.opacity(0.2), lineWidth: 1)
    }
}

// MARK: - Radar Data Polygon

/// The filled polygon representing actual stat values
struct RadarDataPolygon: View {
    let center: CGPoint
    let radius: CGFloat
    let stats: [Stat]
    let maxValue: Double
    let progress: CGFloat

    var body: some View {
        ZStack {
            // Filled area
            Path { path in
                let points = dataPoints()
                guard let first = points.first else { return }

                path.move(to: first)
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [
                        SystemTheme.primaryBlue.opacity(0.4),
                        SystemTheme.primaryPurple.opacity(0.3)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            // Border stroke
            Path { path in
                let points = dataPoints()
                guard let first = points.first else { return }

                path.move(to: first)
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
                path.closeSubpath()
            }
            .stroke(
                LinearGradient(
                    colors: [SystemTheme.primaryBlue, SystemTheme.primaryPurple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 2
            )
            .glow(color: SystemTheme.primaryBlue, radius: 5)

            // Data points with glow
            ForEach(Array(dataPoints().enumerated()), id: \.offset) { index, point in
                Circle()
                    .fill(stats[index].type.color)
                    .frame(width: 10, height: 10)
                    .position(point)
                    .glow(color: stats[index].type.color, radius: 6)
            }
        }
    }

    private func dataPoints() -> [CGPoint] {
        guard stats.count == 6 else { return [] }

        var points: [CGPoint] = []
        for (index, stat) in stats.enumerated() {
            let angle = CGFloat(index) * (2 * .pi / 6) - .pi / 2
            let value = min(Double(stat.totalValue), maxValue)
            let normalizedValue = CGFloat(value / maxValue) * progress
            let pointRadius = radius * normalizedValue

            let x = center.x + pointRadius * cos(angle)
            let y = center.y + pointRadius * sin(angle)
            points.append(CGPoint(x: x, y: y))
        }
        return points
    }
}

// MARK: - Radar Stat Labels

/// Labels around the radar chart showing stat names and values
struct RadarStatLabels: View {
    let center: CGPoint
    let radius: CGFloat
    let stats: [Stat]

    var body: some View {
        ForEach(Array(stats.enumerated()), id: \.element.id) { index, stat in
            let angle = CGFloat(index) * (2 * .pi / 6) - .pi / 2
            let x = center.x + radius * cos(angle)
            let y = center.y + radius * sin(angle)

            VStack(spacing: 2) {
                Text(stat.type.rawValue)
                    .font(SystemTypography.mono(12, weight: .bold))
                    .foregroundStyle(stat.type.color)

                Text("\(stat.totalValue)")
                    .font(SystemTypography.mono(16, weight: .bold))
                    .foregroundStyle(SystemTheme.textPrimary)
            }
            .position(x: x, y: y)
        }
    }
}

// MARK: - Helper Functions

/// Calculate points for a regular polygon
private func polygonPoints(center: CGPoint, radius: CGFloat, sides: Int) -> [CGPoint] {
    var points: [CGPoint] = []
    for i in 0..<sides {
        let angle = CGFloat(i) * (2 * .pi / CGFloat(sides)) - .pi / 2
        let x = center.x + radius * cos(angle)
        let y = center.y + radius * sin(angle)
        points.append(CGPoint(x: x, y: y))
    }
    return points
}

// MARK: - Mini Radar Chart

/// A smaller, simplified radar chart for compact displays
struct MiniRadarChartView: View {
    let stats: [Stat]
    let size: CGFloat

    var body: some View {
        RadarChartView(stats: stats, animated: false)
            .frame(width: size, height: size)
    }
}

// MARK: - Animated Stat Change

/// Shows an animated stat increase effect
struct StatIncreaseView: View {
    let statType: StatType
    let amount: Int

    @State private var opacity: Double = 1.0
    @State private var offsetY: CGFloat = 0
    @State private var scale: CGFloat = 1.0

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: statType.icon)
                .font(.system(size: 16))
                .foregroundStyle(statType.color)

            Text("+\(amount)")
                .font(SystemTypography.mono(18, weight: .bold))
                .foregroundStyle(statType.color)

            Text(statType.rawValue)
                .font(SystemTypography.mono(14, weight: .semibold))
                .foregroundStyle(statType.color.opacity(0.8))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(statType.color.opacity(0.2))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(statType.color.opacity(0.5), lineWidth: 1)
        )
        .glow(color: statType.color, radius: 8)
        .scaleEffect(scale)
        .offset(y: offsetY)
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) {
                scale = 1.2
            }
            withAnimation(.easeOut(duration: 0.3).delay(0.3)) {
                scale = 1.0
            }
            withAnimation(.easeOut(duration: 1.5).delay(0.5)) {
                offsetY = -50
                opacity = 0
            }
        }
    }
}

// MARK: - Preview

#Preview("Radar Chart") {
    ZStack {
        SystemTheme.backgroundPrimary
            .ignoresSafeArea()

        VStack {
            Text("PLAYER STATUS")
                .font(SystemTypography.systemTitle)
                .foregroundStyle(SystemTheme.primaryBlue)

            RadarChartView(
                stats: [
                    Stat(type: .strength, baseValue: 45),
                    Stat(type: .intelligence, baseValue: 72),
                    Stat(type: .agility, baseValue: 38),
                    Stat(type: .vitality, baseValue: 55),
                    Stat(type: .willpower, baseValue: 62),
                    Stat(type: .spirit, baseValue: 48)
                ]
            )
            .frame(width: 300, height: 300)
            .padding()
        }
    }
}

#Preview("Stat Increase Animation") {
    ZStack {
        SystemTheme.backgroundPrimary
            .ignoresSafeArea()

        VStack(spacing: 20) {
            StatIncreaseView(statType: .strength, amount: 10)
            StatIncreaseView(statType: .intelligence, amount: 25)
            StatIncreaseView(statType: .spirit, amount: 5)
        }
    }
}
