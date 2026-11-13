import ReplyRightCore
import ReplyRightUI
import StoreKit
import SwiftUI

struct YouTab: View {
    var body: some View {
        NavigationStack {
            YouView()
        }
    }
}

/// Everything about the user and their setup: voice, people, keyboard, plan, privacy.
struct YouView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var showsManageSubscription = false
    @State private var isRestoring = false

    var body: some View {
        @Bindable var app = app

        ScreenScroll {
            ScreenHeader(
                lead: "All about you",
                emphasis: ""
            )
            .padding(.top, RRSpace.l)

            planCard

            VStack(spacing: 0) {
                NavigationLink {
                    MyVoiceView()
                } label: {
                    NavigationRow(title: "My Voice", subtitle: "How you text, so suggestions sound like you.", systemImage: "waveform")
                }
                .accessibilityIdentifier("you-voice")
                rowDivider
                NavigationLink {
                    PeopleView()
                } label: {
                    NavigationRow(
                        title: "People",
                        subtitle: "Context about who you're talking to.",
                        systemImage: "person.2",
                        trailing: app.people.isEmpty ? nil : "\(app.people.count)"
                    )
                }
                rowDivider
                NavigationLink {
                    KeyboardSetupView()
                } label: {
                    NavigationRow(title: "ReplyRight keyboard", subtitle: "Suggestions right where you type.", systemImage: "keyboard")
                }
                .accessibilityIdentifier("you-keyboard")
                rowDivider
                NavigationLink {
                    PrivacyCenterView()
                } label: {
                    NavigationRow(title: "Privacy Center", subtitle: "What's sent, what's stored, and how to delete it.", systemImage: "lock.shield")
                }
                .accessibilityIdentifier("you-privacy")
                rowDivider
                Button {
                    app.showsConnection = true
                } label: {
                    NavigationRow(
                        title: "Connection",
                        subtitle: app.connection.title,
                        systemImage: "antenna.radiowaves.left.and.right"
                    )
                }
                .accessibilityIdentifier("you-connection")
            }
            .buttonStyle(.rrPress)
            .rrCard(padding: RRSpace.xs)

            VStack(alignment: .leading, spacing: RRSpace.m) {
                ChoiceGroup(
                    title: "Appearance",
                    options: AppSettings.Appearance.allCases,
                    label: { $0.title },
                    selection: $app.settings.appearance
                )
                Toggle(isOn: $app.settings.hapticsEnabled) {
                    Text("Haptics")
                        .rrText(.headline)
                        .foregroundStyle(Color.rrText)
                }
                .tint(Color.rrAccent)
            }
            .rrCard()

            VStack(spacing: 0) {
                Button {
                    openURL(AppConfig.supportURL(base: app.apiBaseURL))
                } label: {
                    NavigationRow(title: "Help and support", systemImage: "questionmark.circle")
                }
                rowDivider
                Button {
                    openURL(AppConfig.termsURL(base: app.apiBaseURL))
                } label: {
                    NavigationRow(title: "Terms of Use", systemImage: "doc.text")
                }
                rowDivider
                Button {
                    openURL(AppConfig.privacyURL(base: app.apiBaseURL))
                } label: {
                    NavigationRow(title: "Privacy Policy", systemImage: "hand.raised")
                }
            }
            .buttonStyle(.rrPress)
            .rrCard(padding: RRSpace.xs)

            Text("ReplyRight \(AppConfig.appVersion) (\(AppConfig.buildNumber))\nSay it better. Be yourself.")
                .rrText(.caption)
                .foregroundStyle(Color.rrTextTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
        }
        .toolbar(.hidden, for: .navigationBar)
        .manageSubscriptionsSheet(isPresented: $showsManageSubscription)
    }

    private var rowDivider: some View {
        Rule()
    }

    // MARK: Plan

    private var planCard: some View {
        VStack(alignment: .leading, spacing: RRSpace.s) {
            Eyebrow("Your plan")
            if app.isPro {
                Text(app.purchases.activePlanName ?? "ReplyRight Pro")
                    .rrText(.title)
                    .foregroundStyle(Color.rrText)
                if let expires = app.purchases.expirationDate {
                    Text("Renews or ends on \(expires.formatted(date: .abbreviated, time: .omitted)).")
                        .rrText(.footnote)
                        .foregroundStyle(Color.rrTextSecondary)
                }
                Button("Manage subscription") {
                    showsManageSubscription = true
                }
                .buttonStyle(.rrSecondaryCompact)
            } else {
                Text("Free")
                    .rrText(.title)
                    .foregroundStyle(Color.rrText)
                Text(freeSummary)
                    .rrText(.footnote)
                    .foregroundStyle(Color.rrTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: RRSpace.xs) {
                    Button("See ReplyRight Pro") {
                        app.paywall = .general
                    }
                    .buttonStyle(RRPrimaryButtonStyle(fullWidth: false))
                    .accessibilityIdentifier("you-see-pro")
                    Button(isRestoring ? "Restoring…" : "Restore") {
                        restore()
                    }
                    .buttonStyle(.rrQuiet)
                    .disabled(isRestoring)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .rrCard()
    }

    private var freeSummary: String {
        let plan = app.plans.free
        var text = "\(plan.dailyGenerations) replies and \(plan.dailyCoachMessages) coaching questions a day."
        if let remaining = app.remainingGenerations {
            text += " \(Microcopy.allowance(remaining: remaining, isPro: false))."
        }
        return text
    }

    private func restore() {
        isRestoring = true
        Task {
            do {
                try await app.purchases.restore()
                app.toast = app.isPro ? "Welcome back. Pro is active." : "No active subscription found for this Apple Account."
            } catch {
                app.toast = "Couldn't reach the App Store. Try again in a moment."
            }
            isRestoring = false
        }
    }
}
