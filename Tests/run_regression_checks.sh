#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/GAMELIFE.xcodeproj"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

echo "Running static regression checks..."

grep -q 'INFOPLIST_KEY_NSHealthShareUsageDescription' "$PROJECT/project.pbxproj" || fail "Missing NSHealthShareUsageDescription"
grep -q 'INFOPLIST_KEY_NSHealthUpdateUsageDescription' "$PROJECT/project.pbxproj" || fail "Missing NSHealthUpdateUsageDescription"
grep -q 'INFOPLIST_KEY_NSLocationWhenInUseUsageDescription = "' "$PROJECT/project.pbxproj" || fail "Missing NSLocationWhenInUseUsageDescription"
grep -q 'INFOPLIST_KEY_NSLocationAlwaysAndWhenInUseUsageDescription = "' "$PROJECT/project.pbxproj" || fail "Missing NSLocationAlwaysAndWhenInUseUsageDescription"

grep -q 'com.apple.developer.family-controls' "$ROOT/GAMELIFE/GAMELIFE.entitlements" || fail "Missing Family Controls entitlement"

if grep -RInF '.preferredColorScheme(.dark)' "$ROOT/GAMELIFE" >/dev/null; then
  fail "Found hard-forced dark mode call(s)"
fi

if grep -RInF 'overrideUserInterfaceStyle' "$ROOT/GAMELIFE" >/dev/null; then
  fail "Found UIKit appearance override forcing color scheme"
fi

grep -q 'allowsBackgroundLocationUpdates = false' "$ROOT/GAMELIFE/Services/LocationManager.swift" || fail "Location manager background updates not disabled"
grep -q 'requestWhenInUseAuthorization()' "$ROOT/GAMELIFE/Services/LocationManager.swift" || fail "Location manager not using requestWhenInUseAuthorization"

if awk '/struct StatusView: View/{flag=1} /\/\/ MARK: - Compact Header View/{flag=0} flag' \
  "$ROOT/GAMELIFE/Views/Status/StatusView.swift" | grep -n 'ScrollView' >/dev/null; then
  fail "Top-level StatusView should remain non-scrollable"
fi

grep -q 'FirstLaunchSetupView' "$ROOT/GAMELIFE/GAMELIFEApp.swift" || fail "First launch setup view missing"
grep -Fq 'loadDailyQuests() ?? []' "$ROOT/GAMELIFE/Services/GameEngine.swift" || fail "GameEngine should not seed default quests"
grep -q 'QuestTrackingType.location' "$ROOT/GAMELIFE/Views/Quests/QuestFormSheet.swift" || fail "Quest form missing Address tracking segment"
grep -q 'Text(\"Schedule\")' "$ROOT/GAMELIFE/Views/Quests/QuestFormSheet.swift" || fail "Quest form missing unified schedule section"
grep -q 'Toggle(\"Enable Reminder\"' "$ROOT/GAMELIFE/Views/Quests/QuestFormSheet.swift" || fail "Quest form missing reminder toggle"
grep -q 'screenTimeSelectionData' "$ROOT/GAMELIFE/Models/QuestModels.swift" || fail "DailyQuest missing Screen Time selection payload"
grep -q 'case workoutCount = \"workoutCount\"' "$ROOT/GAMELIFE/Views/Quests/QuestFormSheet.swift" || fail "Quest form missing workout-count HealthKit option"
grep -q 'healthKitDataDidUpdate' "$ROOT/GAMELIFE/Services/HealthKitManager.swift" || fail "HealthKit update notification missing"
grep -q 'healthKitDataDidUpdate' "$ROOT/GAMELIFE/Services/GameEngine.swift" || fail "GameEngine should react to HealthKit updates"
grep -q 'screenTimeDataDidUpdate' "$ROOT/GAMELIFE/Services/GameEngine.swift" || fail "GameEngine should react to Screen Time updates"
grep -q 'checkQuestProgress(for quest: DailyQuest)' "$ROOT/GAMELIFE/Services/ScreenTimeManager.swift" || fail "Screen Time quest progress evaluator missing"
grep -q 'minimumVisitMinutes: configuredMinimumStay' "$ROOT/GAMELIFE/Services/LocationManager.swift" || fail "Location quest dwell-time configuration missing"
grep -q 'failForAppExit' "$ROOT/GAMELIFE/Services/TrainingManager.swift" || fail "Training manager missing app-exit fail handler"
grep -q 'phase == .background && trainingManager.isActive' "$ROOT/GAMELIFE/Views/Training/TrainingView.swift" || fail "Training view missing background fail trigger"
grep -q 'maxHP' "$ROOT/GAMELIFE/Models/PlayerModels.swift" || fail "Player HP model missing"
grep -q 'awardXP(xp)' "$ROOT/GAMELIFE/Services/TrainingManager.swift" || fail "Training rewards should route through GameEngine.awardXP"

if grep -RInF 'Text("[QUESTS]")' "$ROOT/GAMELIFE/Views" >/dev/null; then
  fail "Found old [QUESTS] badge"
fi

if grep -RInF 'Text("[TRAINING]")' "$ROOT/GAMELIFE/Views" >/dev/null; then
  fail "Found old [TRAINING] badge"
fi

if grep -RInF 'Text("[BOSSES]")' "$ROOT/GAMELIFE/Views" >/dev/null; then
  fail "Found old [BOSSES] badge"
fi

echo "Running model logic tests..."
swiftc -o /tmp/gamelife_model_logic_tests \
  "$ROOT/Tests/test_theme_stub.swift" \
  "$ROOT/GAMELIFE/Models/PlayerModels.swift" \
  "$ROOT/GAMELIFE/Models/QuestModels.swift" \
  "$ROOT/GAMELIFE/Models/ActivityLogModels.swift" \
  "$ROOT/Tests/model_logic_tests.swift"
/tmp/gamelife_model_logic_tests

echo "Running project build..."
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild \
  -project "$PROJECT" \
  -scheme GAMELIFE \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build >/tmp/gamelife_regression_build.log 2>&1 || {
  tail -n 120 /tmp/gamelife_regression_build.log
  fail "xcodebuild failed"
}

echo "All regression checks passed."
