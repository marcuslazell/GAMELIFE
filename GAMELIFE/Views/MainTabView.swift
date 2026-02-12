//
//  MainTabView.swift
//  GAMELIFE
//
//  [SYSTEM]: Navigation matrix initialized.
//  Your journey through the realms begins here.
//

import SwiftUI

// MARK: - Main Tab View

/// The root navigation structure - 5 distinct tabs for the Hunter's journey
struct MainTabView: View {

    // MARK: - Properties

    @EnvironmentObject var gameEngine: GameEngine
    @AppStorage("defaultTab") private var defaultTab: Int = 0
    @State private var selectedTab: Int

    // MARK: - System Message State

    @State private var currentSystemMessage: SystemMessage?

    // MARK: - Initialization

    init() {
        // Initialize to user's preferred default tab
        let savedDefault = UserDefaults.standard.integer(forKey: "defaultTab")
        _selectedTab = State(initialValue: savedDefault)
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $selectedTab) {
                // Tab 0: Status (Player Profile & Stats)
                StatusView()
                    .tabItem {
                        Label("Status", systemImage: "person.fill")
                    }
                    .tag(0)

                // Tab 1: Quests (Daily/Micro Tasks)
                QuestsView()
                    .tabItem {
                        Label("Quests", systemImage: "list.bullet.rectangle")
                    }
                    .tag(1)

                // Tab 2: Training (Focus Timer - formerly Dungeon)
                TrainingView()
                    .tabItem {
                        Label("Training", systemImage: "timer")
                    }
                    .tag(2)

                // Tab 3: Bosses (Projects & Long-term Goals)
                BossesView()
                    .tabItem {
                        Label("Bosses", systemImage: "bolt.shield.fill")
                    }
                    .tag(3)

                // Tab 4: Shop (Rewards Marketplace)
                ShopView()
                    .tabItem {
                        Label("Shop", systemImage: "bag.fill")
                    }
                    .tag(4)
            }
            .tint(SystemTheme.primaryBlue)

            // System Message Banner Overlay
            if let message = currentSystemMessage {
                SystemMessageBanner(message: message) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        currentSystemMessage = nil
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(100)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSystemMessage)) { notification in
            if let message = notification.object as? SystemMessage {
                withAnimation(.easeOut(duration: 0.22)) {
                    currentSystemMessage = message
                }
            }
        }
        .onChange(of: defaultTab) { _, newValue in
            selectedTab = newValue
        }
    }
}

// MARK: - Tab Enum

/// The five pillars of the Hunter's interface
enum GameTab: Int, CaseIterable {
    case status = 0
    case quests = 1
    case training = 2
    case bosses = 3
    case shop = 4

    var title: String {
        switch self {
        case .status: return "Status"
        case .quests: return "Quests"
        case .training: return "Training"
        case .bosses: return "Bosses"
        case .shop: return "Shop"
        }
    }

    var icon: String {
        switch self {
        case .status: return "person.fill"
        case .quests: return "list.bullet.rectangle"
        case .training: return "timer"
        case .bosses: return "bolt.shield.fill"
        case .shop: return "bag.fill"
        }
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let showSystemMessage = Notification.Name("showSystemMessage")
}

// MARK: - Preview

#Preview {
    MainTabView()
        .environmentObject(GameEngine.shared)
}
