//
//  ActivityLogModels.swift
//  GAMELIFE
//
//  Tracks recent player actions for the status log.
//

import Foundation
import SwiftUI

enum ActivityLogType: String, Codable {
    case questCompleted
    case bossDefeated
    case rewardConsumed

    var icon: String {
        switch self {
        case .questCompleted: return "checkmark.seal.fill"
        case .bossDefeated: return "bolt.shield.fill"
        case .rewardConsumed: return "gift.fill"
        }
    }

    var color: Color {
        switch self {
        case .questCompleted: return SystemTheme.successGreen
        case .bossDefeated: return SystemTheme.criticalRed
        case .rewardConsumed: return SystemTheme.goldColor
        }
    }
}

struct ActivityLogEntry: Codable, Identifiable {
    let id: UUID
    let type: ActivityLogType
    let title: String
    let detail: String
    let timestamp: Date

    init(
        id: UUID = UUID(),
        type: ActivityLogType,
        title: String,
        detail: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.detail = detail
        self.timestamp = timestamp
    }
}
