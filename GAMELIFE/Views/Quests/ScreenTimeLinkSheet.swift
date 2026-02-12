//
//  ScreenTimeLinkSheet.swift
//  GAMELIFE
//
//  [SYSTEM]: Neural Link interface active.
//  Connect your mind activity to the System.
//

import SwiftUI
import FamilyControls

// MARK: - Screen Time Link Sheet

/// Wrapper for FamilyActivityPicker to select apps for quest tracking
struct ScreenTimeLinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: FamilyActivitySelection

    @StateObject private var screenTimeManager = ScreenTimeManager.shared
    @State private var showAuthorizationError = false
    @State private var authorizationErrorMessage = "Screen Time access is required to track app usage."

    var body: some View {
        NavigationStack {
            ZStack {
                SystemTheme.backgroundPrimary
                    .ignoresSafeArea()

                if screenTimeManager.isAuthorized {
                    VStack(spacing: 0) {
                        // Header info
                        VStack(spacing: SystemSpacing.sm) {
                            Image(systemName: "apps.iphone")
                                .font(.system(size: 40))
                                .foregroundStyle(SystemTheme.primaryBlue)

                            Text("Select Apps to Track")
                                .font(SystemTypography.titleSmall)
                                .foregroundStyle(SystemTheme.textPrimary)

                            Text("Choose which apps count toward completing this quest")
                                .font(SystemTypography.caption)
                                .foregroundStyle(SystemTheme.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                        .background(SystemTheme.backgroundSecondary)

                        // Family Activity Picker
                        FamilyActivityPicker(selection: $selection)
                            .ignoresSafeArea()
                    }
                } else {
                    // Authorization required view
                    AuthorizationRequiredView(
                        onRequestAuth: requestAuthorization
                    )
                }
            }
            .navigationTitle("Screen Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        screenTimeManager.selectedAppsToTrack = selection
                        dismiss()
                    }
                    .disabled(!screenTimeManager.isAuthorized)
                }
            }
            .alert("Authorization Required", isPresented: $showAuthorizationError) {
                Button("Open Settings") {
                    openSettings()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(authorizationErrorMessage)
            }
            .onAppear {
                screenTimeManager.refreshAuthorizationStatus()
                if !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty {
                    screenTimeManager.selectedAppsToTrack = selection
                }
            }
            .onChange(of: selection) { _, newSelection in
                screenTimeManager.selectedAppsToTrack = newSelection
            }
        }
    }

    // MARK: - Actions

    private func requestAuthorization() {
        Task {
            do {
                try await screenTimeManager.requestAuthorization()
                screenTimeManager.startUsageMonitoring()
            } catch {
                authorizationErrorMessage = error.localizedDescription.isEmpty
                    ? "Screen Time access is required to track app usage. Please enable it in Settings."
                    : error.localizedDescription
                showAuthorizationError = true
            }
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Authorization Required View

struct AuthorizationRequiredView: View {
    let onRequestAuth: () -> Void

    var body: some View {
        VStack(spacing: SystemSpacing.lg) {
            // Icon
            ZStack {
                Circle()
                    .fill(SystemTheme.primaryBlue.opacity(0.1))
                    .frame(width: 100, height: 100)

                Image(systemName: "brain.head.profile")
                    .font(.system(size: 48))
                    .foregroundStyle(SystemTheme.primaryBlue)
            }

            // Title
            Text("Neural Link Required")
                .font(SystemTypography.titleSmall)
                .foregroundStyle(SystemTheme.textPrimary)

            // Description
            VStack(spacing: SystemSpacing.sm) {
                Text("[SYSTEM]: Mind activity monitoring not connected.")
                    .font(SystemTypography.systemMessage)
                    .foregroundStyle(SystemTheme.primaryBlue)

                Text("To track app usage automatically, GAMELIFE needs access to Screen Time data.")
                    .font(SystemTypography.caption)
                    .foregroundStyle(SystemTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, SystemSpacing.xl)

            // Benefits
            VStack(alignment: .leading, spacing: SystemSpacing.sm) {
                NeuralLinkBenefit(
                    icon: "checkmark.circle.fill",
                    text: "Auto-complete quests based on app usage"
                )
                NeuralLinkBenefit(
                    icon: "chart.bar.fill",
                    text: "Track reading, learning, and focus time"
                )
                NeuralLinkBenefit(
                    icon: "shield.fill",
                    text: "Monitor screen time habits"
                )
            }
            .padding()
            .background(SystemTheme.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: SystemRadius.medium))
            .padding(.horizontal)

            // Connect button
            Button(action: onRequestAuth) {
                HStack {
                    Image(systemName: "link.circle.fill")
                    Text("Establish Neural Link")
                }
                .font(SystemTypography.mono(14, weight: .bold))
                .foregroundStyle(SystemTheme.backgroundPrimary)
                .frame(maxWidth: .infinity)
                .padding()
                .background(SystemTheme.primaryBlue)
                .clipShape(RoundedRectangle(cornerRadius: SystemRadius.medium))
            }
            .padding(.horizontal, SystemSpacing.xl)
            .padding(.top, SystemSpacing.md)

            Spacer()
        }
        .padding(.top, SystemSpacing.xl)
    }
}

// MARK: - Neural Link Benefit Row

struct NeuralLinkBenefit: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: SystemSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(SystemTheme.successGreen)
                .frame(width: 24)

            Text(text)
                .font(SystemTypography.bodySmall)
                .foregroundStyle(SystemTheme.textPrimary)

            Spacer()
        }
    }
}

// MARK: - Selected Apps Summary

struct SelectedAppsSummary: View {
    let selection: FamilyActivitySelection

    var body: some View {
        VStack(alignment: .leading, spacing: SystemSpacing.sm) {
            Text("Selected Apps")
                .font(SystemTypography.caption)
                .foregroundStyle(SystemTheme.textSecondary)

            if selection.applicationTokens.isEmpty && selection.categoryTokens.isEmpty {
                HStack {
                    Image(systemName: "app.dashed")
                        .foregroundStyle(SystemTheme.textTertiary)
                    Text("No apps selected")
                        .font(SystemTypography.bodySmall)
                        .foregroundStyle(SystemTheme.textTertiary)
                }
            } else {
                HStack {
                    if !selection.applicationTokens.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "app.fill")
                                .font(.system(size: 12))
                            Text("\(selection.applicationTokens.count) app(s)")
                                .font(SystemTypography.mono(12, weight: .semibold))
                        }
                        .foregroundStyle(SystemTheme.primaryBlue)
                    }

                    if !selection.categoryTokens.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 12))
                            Text("\(selection.categoryTokens.count) category(s)")
                                .font(SystemTypography.mono(12, weight: .semibold))
                        }
                        .foregroundStyle(SystemTheme.primaryPurple)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SystemTheme.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: SystemRadius.small))
    }
}

// MARK: - Preview

#Preview {
    ScreenTimeLinkSheet(selection: .constant(FamilyActivitySelection()))
}
