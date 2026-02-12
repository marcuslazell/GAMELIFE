import SwiftUI

// Minimal theme stub for standalone model logic tests.
// This avoids pulling UIKit-dependent app theme code into the test binary.
struct SystemTheme {
    static let statStrength = Color.red
    static let statIntelligence = Color.blue
    static let statAgility = Color.green
    static let statVitality = Color.orange
    static let statWillpower = Color.purple
    static let statSpirit = Color.yellow

    static let primaryBlue = Color.blue
    static let primaryPurple = Color.purple

    static let successGreen = Color.green
    static let criticalRed = Color.red
    static let goldColor = Color.yellow
}
