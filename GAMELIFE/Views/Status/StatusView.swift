//
//  StatusView.swift
//  GAMELIFE
//
//  [SYSTEM]: Status window activated.
//  Your power level is now visible.
//

import SwiftUI

// MARK: - Status View

/// Tab 1: Player profile with compact radar chart, stats, and recent activity.
/// Designed to fit on-screen without vertical scrolling.
struct StatusView: View {

    @EnvironmentObject var gameEngine: GameEngine
    @State private var isActivityLogExpanded = false

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                // Geometry inside TabView already reflects available content space.
                // Use that directly so we don't double-subtract tab bar/safe areas.
                let availableHeight = max(420, geometry.size.height)
                let isCompactHeight = availableHeight < 720
                let isLargeHeight = availableHeight >= 860

                let stackSpacing = isCompactHeight ? 10.0 : (isLargeHeight ? 18.0 : 14.0)
                let headerHeight = max(82, min(availableHeight * (isCompactHeight ? 0.15 : 0.165), isLargeHeight ? 136 : 124))
                let radarHeight = max(168, min(availableHeight * (isCompactHeight ? 0.31 : 0.36), isLargeHeight ? 336 : 302))
                let bottomPadding = isCompactHeight ? 8.0 : 12.0
                let remainingBottomHeight = availableHeight - headerHeight - radarHeight - (stackSpacing * 2) - bottomPadding
                let bottomSectionHeight = max(0, remainingBottomHeight)
                VStack(spacing: stackSpacing) {
                    CompactHeaderView(player: gameEngine.player, isCompact: isCompactHeight)
                        .frame(height: headerHeight)

                    RadarChartView(stats: gameEngine.player.statArray)
                        .frame(height: radarHeight)
                        .padding(.horizontal, SystemSpacing.md)

                    StatusBottomSection(
                        stats: gameEngine.player.statArray,
                        activities: gameEngine.recentActivity,
                        isCompact: isCompactHeight,
                        isLargeHeight: isLargeHeight,
                        containerHeight: bottomSectionHeight,
                        isActivityLogExpanded: isActivityLogExpanded,
                        onToggleActivityLog: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isActivityLogExpanded.toggle()
                            }
                        }
                    )
                    .frame(height: bottomSectionHeight, alignment: .top)
                }
                .padding(.bottom, bottomPadding)
            }
            .background(SystemTheme.backgroundPrimary)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(SystemTheme.textSecondary)
                    }
                }
            }
            .toolbarBackground(SystemTheme.backgroundPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

// MARK: - Compact Header View

struct CompactHeaderView: View {
    let player: Player
    let isCompact: Bool

    @State private var glowIntensity: Double = 0.5

    private var xpProgress: Double {
        min(1, max(0, player.xpProgress))
    }

    var body: some View {
        HStack(spacing: isCompact ? SystemSpacing.sm : SystemSpacing.md) {
            ZStack {
                Circle()
                    .fill(player.rank.glowColor.opacity(0.2))
                    .frame(width: isCompact ? 44 : 50, height: isCompact ? 44 : 50)

                Circle()
                    .stroke(player.rank.glowColor, lineWidth: 2)
                    .frame(width: isCompact ? 44 : 50, height: isCompact ? 44 : 50)
                    .glow(color: player.rank.glowColor, radius: 6 * glowIntensity)

                Text(player.rank.rawValue)
                    .font(SystemTypography.mono(isCompact ? 14 : 16, weight: .bold))
                    .foregroundStyle(player.rank.glowColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(player.name)
                    .font(isCompact ? SystemTypography.bodySmall : SystemTypography.headline)
                    .foregroundStyle(SystemTheme.textPrimary)
                    .lineLimit(1)
                    .layoutPriority(1)

                HStack(spacing: 6) {
                    Text("Lv. \(player.level)")
                        .font(SystemTypography.mono(isCompact ? 12 : 13, weight: .bold))
                        .foregroundStyle(SystemTheme.primaryBlue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(2)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(SystemTheme.backgroundSecondary)

                            RoundedRectangle(cornerRadius: 2)
                                .fill(SystemTheme.xpGradient)
                                .frame(width: geo.size.width * xpProgress)
                        }
                    }
                    .frame(width: isCompact ? 68 : 80, height: 6)
                    .layoutPriority(0)
                }

                Text("\(player.currentXP)/\(player.xpRequiredForNextLevel) XP")
                    .font(SystemTypography.captionSmall)
                    .foregroundStyle(SystemTheme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: isCompact ? 13 : 14))
                        .foregroundStyle(SystemTheme.goldColor)

                    Text("\(player.gold)")
                        .font(SystemTypography.mono(isCompact ? 13 : 14, weight: .bold))
                        .foregroundStyle(SystemTheme.goldColor)
                }

                if player.currentStreak > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(SystemTheme.warningOrange)

                        Text("\(player.currentStreak)d")
                            .font(SystemTypography.mono(12, weight: .semibold))
                            .foregroundStyle(SystemTheme.warningOrange)
                    }
                }

                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: isCompact ? 11 : 12))
                        .foregroundStyle(SystemTheme.criticalRed)

                    Text("\(player.currentHP)/\(player.maxHP)")
                        .font(SystemTypography.mono(isCompact ? 11 : 12, weight: .semibold))
                        .foregroundStyle(SystemTheme.criticalRed)
                }
            }
        }
        .padding(.horizontal, SystemSpacing.md)
        .padding(.vertical, isCompact ? SystemSpacing.xs : SystemSpacing.sm)
        .background(SystemTheme.backgroundSecondary)
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                glowIntensity = 1.0
            }
        }
    }
}

// MARK: - Bottom Section

struct StatusBottomSection: View {
    let stats: [Stat]
    let activities: [ActivityLogEntry]
    let isCompact: Bool
    let isLargeHeight: Bool
    let containerHeight: CGFloat
    let isActivityLogExpanded: Bool
    let onToggleActivityLog: () -> Void

    var body: some View {
        let sectionSpacing = isCompact ? SystemSpacing.sm : (isLargeHeight ? SystemSpacing.md : SystemSpacing.sm)
        let verticalPadding = isCompact ? SystemSpacing.xs : SystemSpacing.sm
        let innerHeight = max(0, containerHeight - (verticalPadding * 2))
        let collapsedActivityHeight: CGFloat = isCompact ? 56 : 64
        let minGridHeight: CGFloat = isCompact ? 148 : 176
        let preferredExpandedHeight = innerHeight * (isCompact ? 0.42 : 0.46)
        let maxExpandedHeight = max(collapsedActivityHeight, innerHeight - minGridHeight - sectionSpacing)
        let expandedActivityHeight = min(maxExpandedHeight, preferredExpandedHeight)
        let activityHeight = isActivityLogExpanded ? max(collapsedActivityHeight, expandedActivityHeight) : collapsedActivityHeight
        let gridHeight = max(0, innerHeight - activityHeight - sectionSpacing)

        let rowSpacing = isCompact ? SystemSpacing.xs : SystemSpacing.sm
        let maxRowHeight: CGFloat = isCompact ? 54 : (isLargeHeight ? 60 : 56)
        let minRowHeight: CGFloat = isCompact ? 38 : 42
        let computedRowHeight = (gridHeight - (rowSpacing * 2)) / 3
        let rowHeight = max(minRowHeight, min(maxRowHeight, computedRowHeight))
        VStack(spacing: sectionSpacing) {
            CompactAttributeGrid(
                stats: stats,
                isCompact: isCompact,
                rowHeight: rowHeight
            )
                .frame(height: gridHeight)
                .clipped()

            RecentActivityLogCard(
                entries: activities,
                isCompact: isCompact,
                isExpanded: isActivityLogExpanded,
                onToggle: onToggleActivityLog,
                expandedContentMaxHeight: max(0, activityHeight - (isCompact ? 54 : 60))
            )
                .frame(height: activityHeight, alignment: .top)
                .clipped()
        }
        .padding(.horizontal, SystemSpacing.md)
        .padding(.vertical, verticalPadding)
    }
}

// MARK: - Compact Attribute Grid

struct CompactAttributeGrid: View {
    let stats: [Stat]
    let isCompact: Bool
    let rowHeight: CGFloat

    private let columns = [
        GridItem(.flexible(), spacing: SystemSpacing.sm),
        GridItem(.flexible(), spacing: SystemSpacing.sm)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: isCompact ? SystemSpacing.xs : SystemSpacing.sm) {
            ForEach(stats) { stat in
                CompactStatRow(
                    stat: stat,
                    isCompact: isCompact,
                    rowHeight: rowHeight
                )
            }
        }
    }
}

// MARK: - Compact Stat Row

struct CompactStatRow: View {
    let stat: Stat
    let isCompact: Bool
    let rowHeight: CGFloat

    private var normalizedProgress: Double {
        min(1.0, max(0.0, Double(stat.totalValue) / 100.0))
    }

    var body: some View {
        HStack(spacing: SystemSpacing.xs) {
            Image(systemName: stat.type.icon)
                .font(.system(size: isCompact ? 14 : 16))
                .foregroundStyle(stat.type.color)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(stat.type.rawValue)
                        .font(SystemTypography.mono(isCompact ? 11 : 12, weight: .bold))
                        .foregroundStyle(stat.type.color)

                    Spacer()

                    Text("\(stat.totalValue)")
                        .font(SystemTypography.mono(isCompact ? 13 : 14, weight: .bold))
                        .foregroundStyle(SystemTheme.textPrimary)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(SystemTheme.backgroundSecondary)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(stat.type.color.opacity(0.7))
                            .frame(width: max(0, geo.size.width * normalizedProgress))
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(.horizontal, isCompact ? SystemSpacing.xs : SystemSpacing.sm)
        .padding(.vertical, isCompact ? 7 : SystemSpacing.xs)
        .frame(height: rowHeight, alignment: .center)
        .background(SystemTheme.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: SystemRadius.small))
    }
}

// MARK: - Recent Activity

struct RecentActivityLogCard: View {
    let entries: [ActivityLogEntry]
    let isCompact: Bool
    let isExpanded: Bool
    let onToggle: () -> Void
    let expandedContentMaxHeight: CGFloat

    private var emptyStateText: String {
        "No recent activity yet. Complete a quest to populate your log."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 6 : SystemSpacing.sm) {
            Button(action: onToggle) {
                HStack(spacing: SystemSpacing.xs) {
                    Text("Recent Activity Log")
                        .font(SystemTypography.mono(isCompact ? 12 : 13, weight: .bold))
                        .foregroundStyle(SystemTheme.primaryBlue)

                    Spacer()

                    if !entries.isEmpty {
                        Text("\(entries.count)")
                            .font(SystemTypography.mono(isCompact ? 11 : 12, weight: .semibold))
                            .foregroundStyle(SystemTheme.textSecondary)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: isCompact ? 11 : 12, weight: .semibold))
                        .foregroundStyle(SystemTheme.primaryBlue)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                if entries.isEmpty {
                    Text(emptyStateText)
                        .font(SystemTypography.captionSmall)
                        .foregroundStyle(SystemTheme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: isCompact ? 6 : SystemSpacing.xs) {
                            ForEach(entries) { entry in
                                ActivityRow(entry: entry, isCompact: isCompact)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: expandedContentMaxHeight)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(isCompact ? SystemSpacing.sm : SystemSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SystemTheme.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: SystemRadius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: SystemRadius.medium)
                .stroke(SystemTheme.borderSecondary, lineWidth: 1)
        )
    }
}

struct ActivityRow: View {
    let entry: ActivityLogEntry
    let isCompact: Bool

    var body: some View {
        HStack(alignment: .top, spacing: SystemSpacing.xs) {
            Image(systemName: entry.type.icon)
                .font(.system(size: isCompact ? 11 : 12, weight: .semibold))
                .foregroundStyle(entry.type.color)
                .frame(width: 16, height: 16)
                .padding(4)
                .background(entry.type.color.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(SystemTypography.bodySmall)
                    .foregroundStyle(SystemTheme.textPrimary)
                    .lineLimit(1)

                Text(entry.detail)
                    .font(SystemTypography.captionSmall)
                    .foregroundStyle(SystemTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Text(entry.timestamp, style: .relative)
                .font(SystemTypography.captionSmall)
                .foregroundStyle(SystemTheme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

// MARK: - Preview

#Preview {
    StatusView()
        .environmentObject(GameEngine.shared)
}
