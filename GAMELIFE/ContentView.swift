//
//  ContentView.swift
//  GAMELIFE
//
//  [SYSTEM]: Legacy view - redirects to RootView
//  Created by Marcus Shaw II on 2/5/26.
//

import SwiftUI

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        RootView(hasCompletedOnboarding: $hasCompletedOnboarding)
            .environmentObject(GameEngine.shared)
    }
}

#Preview {
    ContentView()
}
