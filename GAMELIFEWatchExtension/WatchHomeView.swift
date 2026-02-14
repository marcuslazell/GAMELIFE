import SwiftUI

struct WatchHomeView: View {
    @EnvironmentObject private var sessionStore: WatchSessionStore

    var body: some View {
        NavigationStack {
            Group {
                if let snapshot = sessionStore.snapshot {
                    List {
                        Section {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(snapshot.playerName)
                                        .font(.headline)
                                    Spacer()
                                    Text("Lv. \(snapshot.level)")
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(.cyan)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    ProgressView(
                                        value: Double(snapshot.currentXP),
                                        total: Double(max(snapshot.xpRequiredForNextLevel, 1))
                                    )
                                    .tint(.cyan)

                                    Text("\(snapshot.currentXP)/\(snapshot.xpRequiredForNextLevel) XP")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }

                                HStack(spacing: 10) {
                                    Label("\(snapshot.gold)", systemImage: "dollarsign.circle.fill")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.yellow)
                                    Label("\(snapshot.currentHP)/\(snapshot.maxHP)", systemImage: "heart.fill")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.red)
                                }

                                Text("\(snapshot.completedToday)/\(snapshot.totalQuests) quests complete today")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Section("Quests") {
                            ForEach(snapshot.quests) { quest in
                                WatchQuestRow(
                                    quest: quest,
                                    isPending: sessionStore.pendingCompletionQuestIDs.contains(quest.id),
                                    onComplete: {
                                        sessionStore.completeQuest(quest)
                                    }
                                )
                            }
                        }
                    }
                    .listStyle(.carousel)
                } else {
                    VStack(spacing: 8) {
                        ProgressView()
                            .tint(.cyan)
                        Text("Waiting for quest sync")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("GAMELIFE")
            .toolbar {
                ToolbarItem {
                    Button {
                        sessionStore.refreshSnapshot()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text(statusLine)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 2)
            }
            .task {
                sessionStore.refreshSnapshot()
            }
        }
    }

    private var statusLine: String {
        if let lastSync = sessionStore.lastSyncDate {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            let relative = formatter.localizedString(for: lastSync, relativeTo: Date())
            return "\(sessionStore.statusMessage) Last sync \(relative)."
        }

        return sessionStore.statusMessage
    }
}

private struct WatchQuestRow: View {
    let quest: WatchQuestSnapshotItem
    let isPending: Bool
    let onComplete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(quest.title)
                    .font(.body.weight(.semibold))
                    .strikethrough(quest.isCompleted)
                    .lineLimit(2)

                Spacer(minLength: 8)

                completionControl
            }

            if !quest.subtitle.isEmpty {
                Text(quest.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if quest.targetValue > 0 {
                ProgressView(value: quest.progressFraction)
                    .tint(quest.isCompleted ? .green : .cyan)
                Text(quest.progressText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(quest.isCompleted ? .green : .secondary)
            }

            HStack(spacing: 8) {
                Label("\(quest.xpReward)", systemImage: "star.fill")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.cyan)
                Label("\(quest.goldReward)", systemImage: "dollarsign.circle.fill")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.yellow)
                Text(quest.trackingType.capitalized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var completionControl: some View {
        if quest.isCompleted {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else if isPending {
            ProgressView()
                .tint(.cyan)
                .scaleEffect(0.75)
        } else {
            Button {
                onComplete()
            } label: {
                Image(systemName: "circle")
                    .foregroundStyle(.cyan)
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    WatchHomeView()
        .environmentObject(WatchSessionStore())
}
