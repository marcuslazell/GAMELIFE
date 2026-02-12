import Foundation
import SwiftUI

@inline(__always)
private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct ModelLogicTestsMain {
    static func main() {
        testPlayerStatsStartAtZero()
        testPlayerHPDefaults()
        testPlayerXPProgressClamping()
        testDailyQuestIdentityPreservation()
        testScreenTimeQuestSelectionPersistence()
        testQuestFrequencyRollovers()
        testLocationQuestMetadata()
        testLinkedQuestBossDamage()
        testDynamicBossGoalTypeMetadata()
        testDynamicBossGoalProgressMath()
        print("All model logic tests passed")
    }

    private static func testPlayerStatsStartAtZero() {
        let player = Player(name: "Tester")
        for type in StatType.allCases {
            let stat = player.stats[type]
            expect(stat != nil, "Player should have stat for \(type.rawValue)")
            expect(stat?.baseValue == 0, "Stat \(type.rawValue) should start at 0")
            expect(stat?.bonusValue == 0, "Stat \(type.rawValue) bonus should start at 0")
            expect(stat?.experience == 0, "Stat \(type.rawValue) XP should start at 0")
        }
    }

    private static func testPlayerHPDefaults() {
        let player = Player(name: "Tester")
        expect(player.maxHP == 100, "Player maxHP should default to 100")
        expect(player.currentHP == 100, "Player currentHP should default to 100")
        expect(abs(player.hpProgress - 1.0) < 0.0001, "HP progress should be full at initialization")
    }

    private static func testPlayerXPProgressClamping() {
        let player = Player(name: "Tester")
        expect(player.xpProgress >= 0 && player.xpProgress <= 1, "Level 1 XP progress should be clamped to 0...1")

        player.level = 3
        player.currentXP = 0
        expect(player.xpProgress == 0, "XP progress should clamp to 0 when XP is below the current level floor")

        player.currentXP = Int.max / 1000
        expect(player.xpProgress <= 1, "XP progress should clamp to 1 for very large XP values")
    }

    private static func testDailyQuestIdentityPreservation() {
        let fixedID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1000)
        let expiresAt = Date(timeIntervalSince1970: 5000)
        let quest = DailyQuest(
            id: fixedID,
            title: "Edited Quest",
            description: "desc",
            difficulty: .normal,
            status: .inProgress,
            targetStats: [.intelligence],
            trackingType: .manual,
            currentProgress: 0.25,
            targetValue: 10,
            unit: "minutes",
            createdAt: createdAt,
            expiresAt: expiresAt
        )

        expect(quest.id == fixedID, "DailyQuest initializer should preserve provided ID")
        expect(quest.status == .inProgress, "DailyQuest initializer should preserve provided status")
        expect(abs(quest.currentProgress - 0.25) < 0.0001, "DailyQuest initializer should preserve provided progress")
        expect(quest.createdAt == createdAt, "DailyQuest initializer should preserve provided creation date")
        expect(quest.expiresAt == expiresAt, "DailyQuest initializer should preserve provided expiry date")
    }

    private static func testScreenTimeQuestSelectionPersistence() {
        let encodedSelection = "selection".data(using: .utf8)
        let quest = DailyQuest(
            title: "Screen Time Quest",
            description: "desc",
            difficulty: .normal,
            targetStats: [.intelligence],
            trackingType: .screenTime,
            targetValue: 30,
            unit: "minutes",
            screenTimeCategory: "1 app",
            screenTimeSelectionData: encodedSelection
        )

        expect(quest.screenTimeSelectionData == encodedSelection, "Screen Time selection payload should persist on the quest")
    }

    private static func testQuestFrequencyRollovers() {
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let hourlyReset = QuestFrequency.hourly.nextResetDate(from: referenceDate)
        let dailyReset = QuestFrequency.daily.nextResetDate(from: referenceDate)
        let weeklyReset = QuestFrequency.weekly.nextResetDate(from: referenceDate)

        expect(hourlyReset > referenceDate, "Hourly reset should be in the future")
        expect(dailyReset > hourlyReset, "Daily reset should be after hourly reset")
        expect(weeklyReset > dailyReset, "Weekly reset should be after daily reset")
    }

    private static func testLocationQuestMetadata() {
        let reminderTime = Date(timeIntervalSince1970: 2_000_000_000)
        let quest = DailyQuest(
            title: "Arrive at Gym",
            description: "Location quest",
            difficulty: .normal,
            targetStats: [.agility],
            frequency: .weekly,
            trackingType: .location,
            targetValue: 1,
            unit: "visits",
            locationCoordinate: LocationCoordinate(
                latitude: 37.33182,
                longitude: -122.03118,
                radius: 804.67,
                locationName: "Apple Park"
            ),
            locationAddress: "1 Apple Park Way, Cupertino, CA",
            linkedBossID: UUID(),
            reminderEnabled: true,
            reminderTime: reminderTime
        )

        expect(quest.resolvedFrequency == .weekly, "Quest should persist selected frequency")
        expect(quest.locationCoordinate?.radius == 804.67, "Location quest should persist configured radius")
        expect(quest.locationAddress == "1 Apple Park Way, Cupertino, CA", "Location address should persist")
        expect(quest.reminderEnabled, "Reminder flag should persist")
        expect(quest.reminderTime == reminderTime, "Reminder time should persist")
        expect(quest.linkedBossID != nil, "Linked boss ID should persist")
    }

    private static func testLinkedQuestBossDamage() {
        let linkedQuest = DailyQuest(
            title: "Linked Quest",
            description: "desc",
            difficulty: .hard,
            targetStats: [.willpower]
        )

        var boss = BossFight(
            title: "Test Boss",
            description: "d",
            difficulty: .hard,
            targetStats: [.willpower],
            maxHP: 100,
            linkedQuestIDs: [linkedQuest.id],
            deadline: nil
        )

        let hpBefore = boss.currentHP
        let damageResult = boss.dealLinkedQuestDamage(from: linkedQuest, playerLevel: 5)
        expect(damageResult.damage > 0, "Linked quest should deal positive damage")
        expect(boss.currentHP < hpBefore, "Boss HP should decrease after linked quest damage")
    }

    private static func testDynamicBossGoalTypeMetadata() {
        expect(DynamicBossGoalType.workoutConsistency.isHealthKitDriven, "Workout consistency should be HealthKit-driven")
        expect(!DynamicBossGoalType.workoutConsistency.isScreenTimeDriven, "Workout consistency should not be ScreenTime-driven")
        expect(DynamicBossGoalType.screenTimeDiscipline.isScreenTimeDriven, "Screen-time discipline should be ScreenTime-driven")
        expect(DynamicBossGoalType.screenTimeDiscipline.unitLabel == "minutes", "Screen-time discipline unit should be minutes")
    }

    private static func testDynamicBossGoalProgressMath() {
        let workout = DynamicBossGoal(
            type: .workoutConsistency,
            startValue: 0,
            targetValue: 4,
            currentValue: 2,
            cadence: .weekly,
            perCadenceTarget: 4,
            generatedQuestID: nil,
            lastUpdatedAt: nil
        )
        expect(abs(workout.normalizedProgress - 0.5) < 0.0001, "Workout dynamic goal should report 50% progress at 2/4 workouts")

        let disciplineAtStart = DynamicBossGoal(
            type: .screenTimeDiscipline,
            startValue: 180,
            targetValue: 60,
            currentValue: 180,
            cadence: .daily,
            perCadenceTarget: 60,
            generatedQuestID: nil,
            lastUpdatedAt: nil
        )
        expect(abs(disciplineAtStart.normalizedProgress) < 0.0001, "Screen-time discipline should be 0% at baseline overuse")

        let disciplineAtGoal = DynamicBossGoal(
            type: .screenTimeDiscipline,
            startValue: 180,
            targetValue: 60,
            currentValue: 60,
            cadence: .daily,
            perCadenceTarget: 60,
            generatedQuestID: nil,
            lastUpdatedAt: nil
        )
        expect(abs(disciplineAtGoal.normalizedProgress - 1.0) < 0.0001, "Screen-time discipline should be 100% at target usage")
    }
}
