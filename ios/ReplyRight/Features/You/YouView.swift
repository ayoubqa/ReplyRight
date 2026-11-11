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
                lead: "All about ",
                emphasis: "you."
            )

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
            }
            .buttonStyle(.rrPress)
            .rrCard(padding: RRSpace.s)

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
            .rrCard(padding: RRSpace.s)

            #if DEBUG
            NavigationLink {
                DeveloperView()
            } label: {
                NavigationRow(title: "Developer", subtitle: app.apiBaseURL.absoluteString, systemImage: "hammer")
            }
            .buttonStyle(.rrPress)
            .rrCard(padding: RRSpace.s)
            #endif

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
        Divider().overlay(Color.rrLine)
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

#if DEBUG
/// Development builds only: point the app at a different backend.
struct DeveloperView: View {
    @Environment(AppModel.self) private var app
    @State private var address = ""

    var body: some View {
        ScreenScroll {
            ScreenHeader(
                lead: "Developer ",
                emphasis: "settings.",
                subtitle: "Only in debug builds. The keyboard and share sheet use the same address."
            )

            VStack(alignment: .leading, spacing: RRSpace.s) {
                Eyebrow("Backend address")
                RRField(AppConfig.defaultAPIBaseURL.absoluteString, text: $address)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Text("Leave empty for the build default. On a real iPhone use your Mac's name, such as http://my-mac.local:3000.")
                    .rrText(.caption)
                    .foregroundStyle(Color.rrTextTertiary)
                HStack(spacing: RRSpace.xs) {
                    Button("Save and check") {
                        app.settings.apiBaseURLOverride = address.trimmed.isEmpty ? nil : address.trimmed
                        Task {
                            await app.refresh(force: true)
                            app.toast = app.mode == nil ? "No response from that address." : "Connected (\(app.mode == .demo ? "demo mode" : "live AI"))."
                        }
                    }
                    .buttonStyle(.rrSecondaryCompact)
                }
            }
            .rrCard()

            VStack(alignment: .leading, spacing: RRSpace.xs) {
                Eyebrow("State")
                Text("Mode: \(app.mode?.rawValue ?? "unknown")")
                Text("Tier (StoreKit): \(app.tier.rawValue)")
                Text("Tier (server): \(app.usage?.tier.rawValue ?? "unknown")")
                Text("App Group available: \(AppGroup.isAvailable ? "yes" : "no")")
            }
            .rrText(.footnote)
            .foregroundStyle(Color.rrTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .rrCard()
        }
        .navigationTitle("Developer")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            address = app.settings.apiBaseURLOverride ?? ""
        }
    }
}
#endif
