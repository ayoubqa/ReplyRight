import ReplyRightCore
import ReplyRightUI
import SwiftUI
import UIKit

/// Everything about the link between this app and its server, in one place.
///
/// It answers four questions without anyone opening a log file: can the server
/// be reached, is it answering with live AI or demo samples, which server is
/// this build talking to, and what happened to the last few requests.
///
/// Nothing here shows a key, a message or a screenshot. The request log holds
/// only addresses, status codes and timings.
struct ConnectionView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    var isSheet = false

    @State private var records: [RequestRecord] = []
    @State private var customAddress = ""
    @State private var isChecking = false
    @FocusState private var addressFocused: Bool

    var body: some View {
        ScreenScroll(spacing: RRSpace.l) {
            status

            server

            if AppConfig.allowsEnvironmentSwitching {
                environments
                liveCheck
            }

            recentRequests
        }
        .navigationTitle("Connection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isSheet {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            customAddress = app.settings.apiBaseURLOverride ?? ""
            await check()
        }
    }

    // MARK: Status

    private var status: some View {
        VStack(alignment: .leading, spacing: RRSpace.s) {
            HStack(alignment: .center, spacing: RRSpace.s) {
                statusGlyph
                EditorialTitle(app.connection.title, style: .title)
            }
            Text(app.connection.summary)
                .rrText(.body)
                .foregroundStyle(Color.rrTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let hint = setupHint {
                Text(hint)
                    .rrText(.callout)
                    .foregroundStyle(Color.rrText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(RRSpace.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: RRRadius.control, style: .continuous).fill(Color.rrSurface)
                    }
            }

            HStack(spacing: RRSpace.s) {
                Button(isChecking ? "Checking…" : "Check again") {
                    Task { await check() }
                }
                .buttonStyle(RRPrimaryButtonStyle(fullWidth: false))
                .disabled(isChecking)
                .accessibilityIdentifier("connection-check")

                if let checked = app.lastChecked {
                    Text("Checked \(checked.formatted(date: .omitted, time: .standard))")
                        .rrText(.footnote)
                        .foregroundStyle(Color.rrTextTertiary)
                }
            }
            .padding(.top, RRSpace.xxs)
        }
    }

    @ViewBuilder
    private var statusGlyph: some View {
        switch app.connection {
        case .checking:
            ProgressView().tint(Color.rrTextSecondary)
        case .live:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(Color.rrSuccess)
        case .demo:
            Image(systemName: "theatermasks.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color.rrHighlightInk)
        case .liveFailing, .unreachable:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(Color.rrDanger)
        case .unknown:
            Image(systemName: "circle.dashed")
                .font(.system(size: 22))
                .foregroundStyle(Color.rrTextTertiary)
        }
    }

    /// Practical advice for whoever is setting the app up. Only shown where a
    /// build can be pointed at a different server; everyone else sees the plain message.
    private var setupHint: String? {
        guard AppConfig.allowsEnvironmentSwitching else { return nil }
        switch app.connection {
        case .unreachable(let error):
            return error.setupHint(for: app.backend)
        case .demo:
            return "To switch on live AI, add ANTHROPIC_API_KEY to backend/.env.local on the server and restart it. The key stays on the server; this app never holds one."
        default:
            return nil
        }
    }

    private func check() async {
        isChecking = true
        await app.checkConnection()
        records = DiagnosticsLog.shared.records
        isChecking = false
    }

    // MARK: Server

    private var server: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("Server")
                .padding(.bottom, RRSpace.xs)
            fact("Address", app.backend.displayAddress)
            fact("This build is set to", app.backend.label)
            if let environment = app.serverEnvironment {
                fact("The server says it is", environment.capitalized)
            }
            if case .live(let model) = app.connection, let model {
                fact("Replies are written by", model)
            }
            fact("App version", "\(AppConfig.appVersion) (\(AppConfig.buildNumber))")
            Rule()
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: RRSpace.s) {
            Text(label)
                .rrText(.callout)
                .foregroundStyle(Color.rrTextSecondary)
            Spacer(minLength: RRSpace.xs)
            Text(value)
                .rrText(.callout)
                .foregroundStyle(Color.rrText)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.vertical, RRSpace.s)
        .overlay(alignment: .top) { Rule() }
        .accessibilityElement(children: .combine)
    }

    // MARK: Environments (development builds)

    private var environments: some View {
        VStack(alignment: .leading, spacing: RRSpace.s) {
            Eyebrow("Which server to use")
            Text("Only in development builds. A release build always uses its own server and ignores these.")
                .rrText(.footnote)
                .foregroundStyle(Color.rrTextTertiary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                ForEach(BackendEnvironment.allCases) { environment in
                    environmentRow(environment)
                }
                Rule()
            }

            VStack(alignment: .leading, spacing: RRSpace.xs) {
                RRField("Or type an address, like http://192.168.1.20:3000", text: $customAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .focused($addressFocused)
                    .submitLabel(.done)
                    .onSubmit { useCustomAddress() }
                    .accessibilityIdentifier("connection-address")

                HStack(spacing: RRSpace.s) {
                    Button("Use this address") { useCustomAddress() }
                        .buttonStyle(.rrSecondaryCompact)
                        .disabled(AppConfig.parseURL(customAddress) == nil)
                    if app.backend.source == .custom {
                        Button("Stop using it") {
                            customAddress = ""
                            app.setBackend(environment: nil, customURL: nil)
                        }
                        .buttonStyle(.rrQuiet)
                    }
                }
                if !customAddress.trimmed.isEmpty, AppConfig.parseURL(customAddress) == nil {
                    Text("Start with http:// or https:// and include the port if there is one.")
                        .rrText(.footnote)
                        .foregroundStyle(Color.rrWarning)
                }
            }
        }
    }

    private func environmentRow(_ environment: BackendEnvironment) -> some View {
        let address = AppConfig.baseURL(for: environment)
        let isCurrent = app.backend.source != .custom && app.backend.environment == environment
        return Button {
            guard address != nil else { return }
            Haptics.select()
            customAddress = ""
            app.setBackend(environment: environment, customURL: nil)
        } label: {
            HStack(alignment: .center, spacing: RRSpace.s) {
                Image(systemName: isCurrent ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isCurrent ? Color.rrAccent : Color.rrTextTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(environment.title)
                        .rrText(.headline)
                        .foregroundStyle(address == nil ? Color.rrTextTertiary : Color.rrText)
                    Text(address?.absoluteString ?? "No address set in Shared.xcconfig yet")
                        .rrText(.footnote)
                        .foregroundStyle(Color.rrTextSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, RRSpace.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Rule() }
            .contentShape(Rectangle())
        }
        .buttonStyle(.rrPress)
        .disabled(address == nil)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private func useCustomAddress() {
        guard AppConfig.parseURL(customAddress) != nil else { return }
        addressFocused = false
        Haptics.select()
        app.setBackend(environment: nil, customURL: customAddress)
    }

    // MARK: Live check (development builds)

    private var liveCheck: some View {
        VStack(alignment: .leading, spacing: RRSpace.s) {
            Eyebrow("Prove the AI works")
            Text("Asks the server to make one small real AI call with a fixed, harmless sentence. Nothing of yours is sent. It tells you whether the server's key and model are actually working.")
                .rrText(.footnote)
                .foregroundStyle(Color.rrTextTertiary)
                .fixedSize(horizontal: false, vertical: true)

            Button(app.isProbing ? "Asking…" : "Run a live check") {
                Task {
                    await app.runProbe()
                    records = DiagnosticsLog.shared.records
                }
            }
            .buttonStyle(.rrSecondaryCompact)
            .disabled(app.isProbing)
            .accessibilityIdentifier("connection-probe")

            if let probe = app.probe {
                HStack(alignment: .top, spacing: RRSpace.xs) {
                    Image(systemName: probe.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(probe.ok ? Color.rrSuccess : Color.rrDanger)
                    Text(probeText(probe))
                        .rrText(.callout)
                        .foregroundStyle(Color.rrText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let error = app.probeError {
                Text(error.setupHint(for: app.backend) ?? error.userMessage)
                    .rrText(.callout)
                    .foregroundStyle(Color.rrTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func probeText(_ probe: ProbeResult) -> String {
        if probe.ok {
            let seconds = Double(probe.latencyMs) / 1000
            let model = probe.model.map { " from \($0)" } ?? ""
            return "Live AI answered\(model) in \(seconds.formatted(.number.precision(.fractionLength(1)))) seconds."
        }
        if probe.mode == .demo {
            return "The server is in demo mode. \(ServerFailure.explain("not_configured"))"
        }
        return "The AI call failed. \(ServerFailure.explain(probe.reason))"
    }

    // MARK: Recent requests

    private var recentRequests: some View {
        VStack(alignment: .leading, spacing: RRSpace.s) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow("Recent requests")
                if !records.isEmpty {
                    Button("Copy report") {
                        UIPasteboard.general.string = DiagnosticsLog.shared.report(target: app.backend, state: app.connection)
                        Haptics.success()
                        app.toast = "Copied. No messages or keys in it."
                    }
                    .buttonStyle(.rrQuiet)
                    .fixedSize()
                }
            }
            Text("Addresses, status codes and timings only. Never your messages or screenshots. Cleared when the app closes.")
                .rrText(.footnote)
                .foregroundStyle(Color.rrTextTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if records.isEmpty {
                Text("Nothing yet.")
                    .rrText(.callout)
                    .foregroundStyle(Color.rrTextSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(records.prefix(15)) { record in
                        RequestRow(record: record)
                    }
                    Rule()
                }
            }
        }
    }
}

private struct RequestRow: View {
    let record: RequestRecord

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: RRSpace.s) {
            Circle()
                .fill(record.succeeded ? Color.rrSuccess : Color.rrDanger)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .rrText(.callout)
                    .foregroundStyle(Color.rrText)
                Text(detail)
                    .rrText(.footnote)
                    .foregroundStyle(Color.rrTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
            Text(record.date.formatted(date: .omitted, time: .standard))
                .rrText(.caption)
                .foregroundStyle(Color.rrTextTertiary)
        }
        .padding(.vertical, RRSpace.s)
        .overlay(alignment: .top) { Rule() }
        .accessibilityElement(children: .combine)
    }

    private var headline: String {
        let status = record.status.map { "HTTP \($0)" } ?? "No answer"
        return "\(record.endpoint.capitalized), \(status)"
    }

    private var detail: String {
        var parts: [String] = []
        if record.succeeded {
            if let mode = record.mode {
                parts.append(mode == "live" ? "Live AI" : "Demo sample")
            }
        } else {
            parts.append(record.outcome.replacingOccurrences(of: "_", with: " "))
            if let reason = record.reason {
                parts.append(ServerFailure.explain(reason))
            }
        }
        parts.append("\(record.durationMs) ms")
        if record.imageCount > 0 {
            parts.append(record.imageCount == 1 ? "1 screenshot" : "\(record.imageCount) screenshots")
        }
        if let id = record.requestID {
            parts.append("id \(id.prefix(8))")
        }
        return parts.joined(separator: ", ")
    }
}
