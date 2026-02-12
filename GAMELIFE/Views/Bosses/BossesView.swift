//
//  BossesView.swift
//  GAMELIFE
//
//  [SYSTEM]: Boss encounter zone accessed.
//  Defeat the monsters blocking your path, Hunter.
//

import SwiftUI

// MARK: - Bosses View

/// Tab 4: Projects & Long-term Goals displayed as Boss Fights
struct BossesView: View {

    // MARK: - Properties

    @EnvironmentObject var gameEngine: GameEngine
    @State private var showCreateBoss = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                SystemTheme.backgroundPrimary
                    .ignoresSafeArea()

                if gameEngine.activeBossFights.isEmpty {
                    EmptyBossState(onCreateTapped: { showCreateBoss = true })
                } else {
                    ScrollView {
                        LazyVStack(spacing: SystemSpacing.md) {
                            ForEach(gameEngine.activeBossFights) { boss in
                                BossCardView(
                                    boss: boss,
                                    onDealDamage: { task in
                                        dealDamage(boss: boss, task: task)
                                    },
                                    onUpdateDynamicValue: { value in
                                        updateDynamicBoss(boss: boss, currentValue: value)
                                    }
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Bosses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreateBoss = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(SystemTheme.primaryBlue)
                    }
                }
            }
            .toolbarBackground(SystemTheme.backgroundPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showCreateBoss) {
                BossFormSheet()
            }
        }
    }

    // MARK: - Actions

    private func dealDamage(boss: BossFight, task: MicroTask) {
        _ = gameEngine.completeMicroTask(bossId: boss.id, taskId: task.id)
    }

    private func updateDynamicBoss(boss: BossFight, currentValue: Double) {
        gameEngine.updateDynamicBossCurrentValue(bossId: boss.id, currentValue: currentValue)
    }
}

// MARK: - Empty Boss State

struct EmptyBossState: View {
    let onCreateTapped: () -> Void

    var body: some View {
        VStack(spacing: SystemSpacing.lg) {
            Image(systemName: "bolt.shield")
                .font(.system(size: 64))
                .foregroundStyle(SystemTheme.textTertiary)

            Text("No Active Boss Fights")
                .font(SystemTypography.titleSmall)
                .foregroundStyle(SystemTheme.textSecondary)

            Text("\"Slay the monsters blocking your path\"")
                .font(SystemTypography.caption)
                .foregroundStyle(SystemTheme.textTertiary)
                .italic()

            Button(action: onCreateTapped) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Create Boss")
                }
                .font(SystemTypography.mono(14, weight: .semibold))
                .foregroundStyle(SystemTheme.primaryBlue)
                .padding()
                .background(SystemTheme.primaryBlue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: SystemRadius.medium))
            }
            .padding(.top, SystemSpacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Boss Card View

struct BossCardView: View {
    @EnvironmentObject var gameEngine: GameEngine
    let boss: BossFight
    let onDealDamage: (MicroTask) -> Void
    let onUpdateDynamicValue: (Double) -> Void

    @State private var isExpanded = false
    @State private var dynamicCurrentInput = ""

    private var linkedQuestTitles: [String] {
        boss.linkedQuestIDs.compactMap { questID in
            gameEngine.dailyQuests.first(where: { $0.id == questID })?.title
        }
    }

    var body: some View {
        VStack(spacing: SystemSpacing.md) {
            // Boss header with HP bar
            VStack(spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(boss.title)
                            .font(SystemTypography.headline)
                            .foregroundStyle(SystemTheme.textPrimary)

                        Text(boss.description)
                            .font(SystemTypography.caption)
                            .foregroundStyle(SystemTheme.textSecondary)
                            .lineLimit(2)
                    }

                    Spacer()

                    // Expand/collapse
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .foregroundStyle(SystemTheme.textSecondary)
                            .padding(8)
                    }
                }

                // HP Bar
                VStack(spacing: 4) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(SystemTheme.backgroundSecondary)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(SystemTheme.hpGradient)
                                .frame(width: geometry.size.width * boss.hpPercentage)
                        }
                    }
                    .frame(height: 16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(SystemTheme.criticalRed.opacity(0.5), lineWidth: 1)
                    )

                    HStack {
                        Text("HP: \(boss.remainingHP) / \(boss.maxHP)")
                            .font(SystemTypography.mono(12, weight: .semibold))
                            .foregroundStyle(SystemTheme.criticalRed)

                        Spacer()

                        Text("\(Int(boss.damageDealtPercentage * 100))% defeated")
                            .font(SystemTypography.captionSmall)
                            .foregroundStyle(SystemTheme.textTertiary)
                    }
                }
            }

            // Micro-tasks (expanded)
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    if let dynamicGoal = boss.dynamicGoal {
                        dynamicGoalSection(dynamicGoal)
                    }

                    Text("Micro-Tasks (Deal Damage)")
                        .font(SystemTypography.caption)
                        .foregroundStyle(SystemTheme.textSecondary)

                    ForEach(boss.microTasks) { task in
                        MicroTaskRow(task: task) {
                            onDealDamage(task)
                        }
                    }

                    if !linkedQuestTitles.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Linked Current Quests")
                                .font(SystemTypography.caption)
                                .foregroundStyle(SystemTheme.primaryBlue)

                            ForEach(linkedQuestTitles, id: \.self) { questTitle in
                                HStack(spacing: 8) {
                                    Image(systemName: "link")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(SystemTheme.primaryBlue)

                                    Text(questTitle)
                                        .font(SystemTypography.captionSmall)
                                        .foregroundStyle(SystemTheme.textSecondary)
                                }
                            }
                        }
                        .padding(10)
                        .background(SystemTheme.backgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: SystemRadius.small))
                    }

                    // Rewards preview
                    HStack {
                        Text("Defeat Rewards:")
                            .font(SystemTypography.captionSmall)
                            .foregroundStyle(SystemTheme.textTertiary)

                        Spacer()

                        HStack(spacing: SystemSpacing.sm) {
                            HStack(spacing: 2) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 10))
                                Text("\(boss.xpReward)")
                                    .font(SystemTypography.mono(11, weight: .semibold))
                            }
                            .foregroundStyle(SystemTheme.primaryBlue)

                            HStack(spacing: 2) {
                                Image(systemName: "dollarsign.circle.fill")
                                    .font(.system(size: 10))
                                Text("\(boss.goldReward)")
                                    .font(SystemTypography.mono(11, weight: .semibold))
                            }
                            .foregroundStyle(SystemTheme.goldColor)
                        }
                    }
                    .padding(.top, SystemSpacing.xs)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .background(SystemTheme.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: SystemRadius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: SystemRadius.medium)
                .stroke(SystemTheme.criticalRed.opacity(0.3), lineWidth: 1)
        )
        .onAppear {
            if let dynamicGoal = boss.dynamicGoal {
                dynamicCurrentInput = String(format: dynamicGoal.type == .savings ? "%.0f" : "%.1f", dynamicGoal.currentValue)
            }
        }
    }

    @ViewBuilder
    private func dynamicGoalSection(_ goal: DynamicBossGoal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Dynamic Goal", systemImage: goal.type.icon)
                    .font(SystemTypography.caption)
                    .foregroundStyle(SystemTheme.primaryBlue)
                Spacer()
                Text(goal.type.rawValue)
                    .font(SystemTypography.mono(11, weight: .semibold))
                    .foregroundStyle(SystemTheme.textSecondary)
            }

            HStack {
                Text("Start: \(formattedGoalValue(goal.startValue, unit: goal.unitLabel))")
                    .font(SystemTypography.captionSmall)
                    .foregroundStyle(SystemTheme.textTertiary)
                Spacer()
                Text("Current: \(formattedGoalValue(goal.currentValue, unit: goal.unitLabel))")
                    .font(SystemTypography.captionSmall)
                    .foregroundStyle(SystemTheme.textSecondary)
                Spacer()
                Text("Target: \(formattedGoalValue(goal.targetValue, unit: goal.unitLabel))")
                    .font(SystemTypography.captionSmall)
                    .foregroundStyle(SystemTheme.successGreen)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(SystemTheme.backgroundSecondary)
                    Capsule()
                        .fill(SystemTheme.primaryBlue)
                        .frame(width: geo.size.width * goal.normalizedProgress)
                }
            }
            .frame(height: 5)

            Text("Progress: \(Int(goal.normalizedProgress * 100))% • Remaining \(formattedGoalValue(goal.remainingAmount, unit: goal.unitLabel))")
                .font(SystemTypography.captionSmall)
                .foregroundStyle(SystemTheme.textSecondary)

            if goal.type == .savings {
                HStack(spacing: 8) {
                    TextField("Current savings", text: $dynamicCurrentInput)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)

                    Button("Update") {
                        if let value = Double(dynamicCurrentInput.replacingOccurrences(of: ",", with: "")) {
                            onUpdateDynamicValue(value)
                        }
                    }
                    .font(SystemTypography.mono(12, weight: .semibold))
                    .foregroundStyle(SystemTheme.primaryBlue)
                    .disabled(Double(dynamicCurrentInput.replacingOccurrences(of: ",", with: "")) == nil)
                }
            } else {
                Text(dynamicSourceText(for: goal.type))
                    .font(SystemTypography.captionSmall)
                    .foregroundStyle(SystemTheme.textTertiary)
            }
        }
        .padding(10)
        .background(SystemTheme.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: SystemRadius.small))
    }

    private func dynamicSourceText(for type: DynamicBossGoalType) -> String {
        switch type {
        case .weight, .bodyFat, .workoutConsistency:
            return "Auto-syncing from Apple Health."
        case .screenTimeDiscipline:
            return "Auto-syncing from Screen Time usage."
        case .savings:
            return "Update manually with your current saved amount."
        }
    }

    private func formattedGoalValue(_ value: Double, unit: String) -> String {
        if unit == "$" {
            return String(format: "$%.0f", value)
        }
        if value.rounded() == value {
            return "\(Int(value))\(unit)"
        }
        return String(format: "%.1f%@", value, unit)
    }
}

// MARK: - Micro Task Row

struct MicroTaskRow: View {
    let task: MicroTask
    let onComplete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onComplete) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isCompleted ? SystemTheme.successGreen : SystemTheme.textTertiary)
            }
            .disabled(task.isCompleted)

            Text(task.title)
                .font(SystemTypography.bodySmall)
                .foregroundStyle(task.isCompleted ? SystemTheme.textTertiary : SystemTheme.textPrimary)
                .strikethrough(task.isCompleted)

            Spacer()

            Text("-\(task.estimatedDamage) HP")
                .font(SystemTypography.mono(12, weight: .semibold))
                .foregroundStyle(SystemTheme.criticalRed)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(SystemTheme.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: SystemRadius.small))
    }
}

// MARK: - Boss Form Sheet

struct BossFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var gameEngine: GameEngine

    @State private var name = ""
    @State private var description = ""
    @State private var maxHP = 1000
    @State private var difficulty: QuestDifficulty = .hard
    @State private var hasDeadline = false
    @State private var deadline = Date().addingTimeInterval(86400 * 7) // 1 week default
    @State private var useDynamicGoal = false
    @State private var dynamicGoalType: DynamicBossGoalType = .weight
    @State private var dynamicStartValue: Double = 180
    @State private var dynamicTargetValue: Double = 170
    @State private var dynamicCurrentValue: Double = 180
    @State private var dynamicCadence: GoalCadence = .weekly
    @State private var dynamicCadenceTarget: Double = 1
    @State private var autoGenerateGoalQuest = true

    // Micro-tasks
    @State private var microTasks: [String] = [""]
    @State private var linkedQuestIDs: Set<UUID> = []

    var isValid: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if useDynamicGoal {
            return abs(dynamicTargetValue - dynamicStartValue) > 0.0001 && dynamicCadenceTarget > 0
        }
        return true
    }

    private var linkableQuests: [DailyQuest] {
        gameEngine.dailyQuests
            .filter { $0.status != .completed }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var selectableDynamicGoalTypes: [DynamicBossGoalType] {
        DynamicBossGoalType.allCases.filter { $0 != .screenTimeDiscipline }
    }

    var body: some View {
        NavigationStack {
            Form {
                // Boss Details
                Section {
                    TextField("Boss Name", text: $name)
                        .font(SystemTypography.body)

                    TextField("Description (Project goal)", text: $description)
                        .font(SystemTypography.body)
                } header: {
                    Text("Boss Details")
                }

                // Combat Stats
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Total HP: \(maxHP)")
                            .font(SystemTypography.mono(14, weight: .semibold))

                        Slider(value: Binding(
                            get: { Double(maxHP) },
                            set: { maxHP = Int($0) }
                        ), in: 100...10000, step: 100)
                        .tint(SystemTheme.criticalRed)

                        Text("Higher HP = more micro-tasks needed to defeat")
                            .font(SystemTypography.captionSmall)
                            .foregroundStyle(SystemTheme.textTertiary)
                    }

                    Picker("Difficulty", selection: $difficulty) {
                        ForEach([QuestDifficulty.normal, .hard, .extreme, .legendary], id: \.self) { diff in
                            Text(diff.rawValue).tag(diff)
                        }
                    }
                } header: {
                    Text("Combat Stats")
                }

                Section {
                    Toggle("Use Dynamic Goal Boss", isOn: $useDynamicGoal)

                    if useDynamicGoal {
                        Picker("Goal Type", selection: $dynamicGoalType) {
                            ForEach(selectableDynamicGoalTypes) { type in
                                Label(type.rawValue, systemImage: type.icon)
                                    .tag(type)
                            }
                        }

                        HStack {
                            Text("Starting Value")
                            Spacer()
                            TextField("Start", value: $dynamicStartValue, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 120)
                            Text(dynamicGoalType.unitLabel)
                                .foregroundStyle(SystemTheme.textSecondary)
                        }

                        HStack {
                            Text("Current Value")
                            Spacer()
                            TextField("Current", value: $dynamicCurrentValue, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 120)
                            Text(dynamicGoalType.unitLabel)
                                .foregroundStyle(SystemTheme.textSecondary)
                        }

                        HStack {
                            Text("Target Value")
                            Spacer()
                            TextField("Target", value: $dynamicTargetValue, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 120)
                            Text(dynamicGoalType.unitLabel)
                                .foregroundStyle(SystemTheme.textSecondary)
                        }

                        Picker("Cadence", selection: $dynamicCadence) {
                            ForEach(GoalCadence.allCases) { cadence in
                                Label(cadence.rawValue, systemImage: cadence.icon)
                                    .tag(cadence)
                            }
                        }

                        HStack {
                            Text("Per-\(dynamicCadence.rawValue) Target")
                            Spacer()
                            TextField("Target", value: $dynamicCadenceTarget, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 120)
                            Text(dynamicGoalType.unitLabel)
                                .foregroundStyle(SystemTheme.textSecondary)
                        }

                        Toggle("Auto-generate linked quest", isOn: $autoGenerateGoalQuest)

                        Text(dynamicGoalExplanation)
                            .font(SystemTypography.captionSmall)
                            .foregroundStyle(SystemTheme.textSecondary)
                    }
                } header: {
                    Text("Dynamic Goal Engine")
                } footer: {
                    Text("Dynamic bosses lose or regain HP based on your real metric progress. Weight/body fat sync from Apple Health. Savings updates from your entered amount.")
                }

                // Deadline
                Section {
                    Toggle("Has Deadline", isOn: $hasDeadline)

                    if hasDeadline {
                        DatePicker(
                            "Deadline",
                            selection: $deadline,
                            in: Date()...,
                            displayedComponents: .date
                        )
                    }
                } header: {
                    Text("Deadline (Optional)")
                }

                // Initial Micro-tasks
                Section {
                    ForEach(microTasks.indices, id: \.self) { index in
                        HStack {
                            TextField("Micro-task \(index + 1)", text: $microTasks[index])
                                .font(SystemTypography.body)

                            if microTasks.count > 1 {
                                Button {
                                    microTasks.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(SystemTheme.criticalRed)
                                }
                            }
                        }
                    }

                    Button {
                        microTasks.append("")
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Micro-task")
                        }
                        .foregroundStyle(SystemTheme.primaryBlue)
                    }
                } header: {
                    Text("Initial Attacks (Micro-tasks)")
                } footer: {
                    Text("Break down your project into small actionable tasks")
                }

                Section {
                    if linkableQuests.isEmpty {
                        Text("No active daily quests available to link.")
                            .font(SystemTypography.caption)
                            .foregroundStyle(SystemTheme.textTertiary)
                    } else {
                        ForEach(linkableQuests) { quest in
                            Button {
                                if linkedQuestIDs.contains(quest.id) {
                                    linkedQuestIDs.remove(quest.id)
                                } else {
                                    linkedQuestIDs.insert(quest.id)
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(quest.title)
                                            .font(SystemTypography.bodySmall)
                                            .foregroundStyle(SystemTheme.textPrimary)

                                        Text(quest.trackingType.isAutomatic ? "Auto-tracked" : "Manual")
                                            .font(SystemTypography.captionSmall)
                                            .foregroundStyle(SystemTheme.textTertiary)
                                    }

                                    Spacer()

                                    Image(systemName: linkedQuestIDs.contains(quest.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(linkedQuestIDs.contains(quest.id) ? SystemTheme.primaryBlue : SystemTheme.textTertiary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Linked Current Quests")
                } footer: {
                    Text("Completing linked quests deals direct damage to this boss. Dynamic bosses also auto-scale linked quest targets to match remaining goal progress.")
                }

                // Rewards Preview
                Section {
                    HStack {
                        Text("XP Reward:")
                            .foregroundStyle(SystemTheme.textSecondary)
                        Spacer()
                        Text("+\(GameFormulas.questXP(difficulty: difficulty) * 10)")
                            .font(SystemTypography.mono(14, weight: .bold))
                            .foregroundStyle(SystemTheme.primaryBlue)
                    }

                    HStack {
                        Text("Gold Reward:")
                            .foregroundStyle(SystemTheme.textSecondary)
                        Spacer()
                        Text("+\(GameFormulas.questGold(difficulty: difficulty) * 10)")
                            .font(SystemTypography.mono(14, weight: .bold))
                            .foregroundStyle(SystemTheme.goldColor)
                    }
                } header: {
                    Text("Defeat Rewards")
                }
            }
            .navigationTitle("Create Boss")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createBoss() }
                        .disabled(!isValid)
                }
            }
            .onChange(of: dynamicGoalType) { _, newType in
                switch newType {
                case .weight:
                    dynamicStartValue = 180
                    dynamicCurrentValue = 180
                    dynamicTargetValue = 170
                    dynamicCadenceTarget = 1
                case .bodyFat:
                    dynamicStartValue = 28
                    dynamicCurrentValue = 28
                    dynamicTargetValue = 20
                    dynamicCadenceTarget = 0.5
                case .savings:
                    dynamicStartValue = 0
                    dynamicCurrentValue = 0
                    dynamicTargetValue = 5000
                    dynamicCadenceTarget = 250
                case .workoutConsistency:
                    dynamicStartValue = 0
                    dynamicCurrentValue = 0
                    dynamicTargetValue = 4
                    dynamicCadence = .weekly
                    dynamicCadenceTarget = 4
                case .screenTimeDiscipline:
                    dynamicStartValue = 180
                    dynamicCurrentValue = 180
                    dynamicTargetValue = 60
                    dynamicCadence = .daily
                    dynamicCadenceTarget = 60
                }
            }
        }
    }

    private var dynamicGoalExplanation: String {
        switch dynamicGoalType {
        case .weight:
            return "Example: start 200lb, goal 180lb. Boss HP will regenerate if weight moves away from 180."
        case .bodyFat:
            return "Example: start 30%, goal 20%. Boss HP tracks actual body fat trend from Health."
        case .savings:
            return "Example: start $0, goal $5000. Update current savings to recalculate boss HP and target quest amount."
        case .workoutConsistency:
            return "Example: start 0, goal 4 weekly workouts. Boss HP drops as HealthKit logs workouts in the active cadence window."
        case .screenTimeDiscipline:
            return "Example: baseline 180 min social media, target 60 min. Boss HP drops when daily social usage trends toward target."
        }
    }

    private func createBoss() {
        let dynamicGoal: DynamicBossGoal? = {
            guard useDynamicGoal else { return nil }
            return DynamicBossGoal(
                type: dynamicGoalType,
                startValue: dynamicStartValue,
                targetValue: dynamicTargetValue,
                currentValue: dynamicCurrentValue,
                cadence: dynamicCadence,
                perCadenceTarget: dynamicCadenceTarget,
                generatedQuestID: nil,
                lastUpdatedAt: Date()
            )
        }()

        let resolvedTargetStats = dynamicGoal?.type.defaultStatTargets ?? [.intelligence, .willpower]

        // Create the boss
        let boss = gameEngine.createBossFight(
            title: name,
            description: description,
            difficulty: difficulty,
            targetStats: resolvedTargetStats,
            maxHP: maxHP,
            linkedQuestIDs: Array(linkedQuestIDs),
            dynamicGoal: dynamicGoal,
            autoGenerateGoalQuest: useDynamicGoal && autoGenerateGoalQuest,
            deadline: hasDeadline ? deadline : nil
        )

        // Add micro-tasks
        for taskTitle in microTasks where !taskTitle.trimmingCharacters(in: .whitespaces).isEmpty {
            gameEngine.addMicroTask(to: boss.id, title: taskTitle, difficulty: .normal)
        }

        dismiss()
    }
}

// MARK: - Preview

#Preview {
    BossesView()
        .environmentObject(GameEngine.shared)
}
