import ReplyRightCore
import ReplyRightUI
import SwiftUI

// Small building blocks used by more than one feature in the app.

/// Pick exactly one option from a short list.
struct ChoiceGroup<Option: Identifiable & Hashable>: View {
    let title: String
    var caption: String? = nil
    let options: [Option]
    let label: (Option) -> String
    @Binding var selection: Option

    var body: some View {
        VStack(alignment: .leading, spacing: RRSpace.s) {
            Eyebrow(title)
            if let caption {
                Text(caption)
                    .rrText(.footnote)
                    .foregroundStyle(Color.rrTextTertiary)
            }
            FlowLayout {
                ForEach(options) { option in
                    RRChip(label(option), isSelected: option == selection) {
                        guard option != selection else { return }
                        selection = option
                        Haptics.select()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Pick any number of options, optionally capped.
struct MultiChoiceGroup<Option: Identifiable & Hashable>: View {
    let title: String
    var caption: String? = nil
    let options: [Option]
    let label: (Option) -> String
    var limit: Int? = nil
    @Binding var selection: [Option]

    var body: some View {
        VStack(alignment: .leading, spacing: RRSpace.s) {
            Eyebrow(title)
            if let caption {
                Text(caption)
                    .rrText(.footnote)
                    .foregroundStyle(Color.rrTextTertiary)
            }
            FlowLayout {
                ForEach(options) { option in
                    RRChip(label(option), isSelected: selection.contains(option)) {
                        toggle(option)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggle(_ option: Option) {
        if let index = selection.firstIndex(of: option) {
            selection.remove(at: index)
        } else {
            if let limit, selection.count >= limit {
                // Swap out the oldest choice rather than refusing the tap.
                selection.removeFirst()
            }
            selection.append(option)
        }
        Haptics.select()
    }
}

/// Chooses whose profile to use as context. Always optional, and always the
/// user's explicit choice: nothing about a person is sent unless they are picked here.
struct PersonPicker: View {
    @Environment(AppModel.self) private var app
    @Binding var selection: CrushProfile?
    var title = "Who's this with?"
    @State private var isAdding = false

    var body: some View {
        VStack(alignment: .leading, spacing: RRSpace.s) {
            Eyebrow(title)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: RRSpace.xs) {
                    RRChip("No one in particular", isSelected: selection == nil) {
                        selection = nil
                        Haptics.select()
                    }
                    ForEach(app.people) { person in
                        RRChip(person.alias, isSelected: selection?.id == person.id) {
                            selection = person
                            app.settings.lastCrushID = person.id
                            Haptics.select()
                        }
                    }
                    RRChip("Add someone", systemImage: "plus") {
                        isAdding = true
                    }
                }
                .padding(.horizontal, RRSpace.screen)
            }
            .padding(.horizontal, -RRSpace.screen)

            if let selection, let fields = sharedSummary(for: selection) {
                Text(fields)
                    .rrText(.footnote)
                    .foregroundStyle(Color.rrTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(isPresented: $isAdding) {
            PersonEditor(person: nil) { created in
                app.savePerson(created)
                selection = created
                app.settings.lastCrushID = created.id
            }
            .environment(app)
            .preferredColorScheme(app.colorScheme)
        }
    }

    /// Says exactly which parts of the profile will travel with the request.
    private func sharedSummary(for person: CrushProfile) -> String? {
        let fields = person.sharedFieldNames
        guard !fields.isEmpty else { return nil }
        return "Used as context for this one: " + fields.joined(separator: ", ").lowercased() + "."
    }
}

/// A profile photo, or the first letter of the name when there is none.
struct PersonAvatar: View {
    @Environment(AppModel.self) private var app
    let person: CrushProfile
    var size: CGFloat = 44
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle().fill(Color.rrAccentSoft)
                Text(person.initial)
                    .font(RRFonts.display(size: size * 0.44))
                    .foregroundStyle(Color.rrAccent)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: "\(person.id.uuidString)-\(person.hasPhoto)-\(person.updatedAt.timeIntervalSince1970)") {
            guard person.hasPhoto, let data = app.store.loadPersonPhoto(person.id) else {
                image = nil
                return
            }
            image = UIImage(data: data)
        }
        .accessibilityHidden(true)
    }
}

/// A screen title block: a quiet line above, the headline in the display face, and a supporting line.
struct ScreenHeader: View {
    var eyebrow: String? = nil
    let lead: String
    let emphasis: String
    var trail: String = ""
    var subtitle: String? = nil
    var style: RRTextStyle = .display

    var body: some View {
        VStack(alignment: .leading, spacing: RRSpace.xs) {
            if let eyebrow {
                Eyebrow(eyebrow)
            }
            EditorialTitle(lead, emphasis: emphasis, trail: trail, style: style)
            if let subtitle {
                Text(subtitle)
                    .rrText(.body)
                    .foregroundStyle(Color.rrTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, RRSpace.xxs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A row that opens something, used in settings-style lists.
struct NavigationRow: View {
    let title: String
    var subtitle: String? = nil
    let systemImage: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: RRSpace.s) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Color.rrAccent)
                .frame(width: 28, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .rrText(.headline)
                    .foregroundStyle(Color.rrText)
                    .multilineTextAlignment(.leading)
                if let subtitle {
                    Text(subtitle)
                        .rrText(.footnote)
                        .foregroundStyle(Color.rrTextSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: RRSpace.xs)
            if let trailing {
                Text(trailing)
                    .rrText(.footnote)
                    .foregroundStyle(Color.rrTextTertiary)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.rrTextTertiary)
        }
        .padding(.vertical, RRSpace.s)
        .contentShape(Rectangle())
    }
}

/// The standard scrolling screen: the ground, generous margins, content from the top.
struct ScreenScroll<Content: View>: View {
    var spacing: CGFloat = RRSpace.l
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) {
                content()
            }
            .padding(.horizontal, RRSpace.screen)
            .padding(.top, RRSpace.s)
            .padding(.bottom, RRSpace.xxl)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .rrScreenBackground()
    }
}

// MARK: - Connection and failure

/// Shown above anything that asks the server for an answer, whenever the
/// answer would not be live AI: demo mode, a server that cannot be reached, or
/// an AI provider that is not answering. Shows nothing when all is well.
struct ConnectionNotice: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        switch app.connection {
        case .demo:
            Button {
                app.showsConnection = true
            } label: {
                DemoBadge(detailed: true)
            }
            .buttonStyle(.rrPress)
            .accessibilityHint("Shows connection details")
        case .unreachable(let error):
            ErrorNote(
                error: error,
                retry: { Task { await app.checkConnection() } },
                secondaryTitle: "Connection details",
                secondaryAction: { app.showsConnection = true }
            )
        case .liveFailing:
            ErrorNote(
                error: .unavailable(message: "ReplyRight's AI isn't answering right now. You can still write and save, and try again in a moment."),
                retry: { Task { await app.checkConnection() } },
                secondaryTitle: "Connection details",
                secondaryAction: { app.showsConnection = true }
            )
        case .unknown, .checking, .live:
            EmptyView()
        }
    }
}

/// A failed request: what happened, a retry when that can help, and a way to
/// the connection screen when the problem is the connection.
struct FailureNote: View {
    @Environment(AppModel.self) private var app
    let error: APIError?
    let message: String
    let retry: () -> Void

    var body: some View {
        if let error {
            ErrorNote(
                error: error,
                retry: retry,
                secondaryTitle: pointsAtConnection(error) ? "Connection details" : nil,
                secondaryAction: pointsAtConnection(error) ? { app.showsConnection = true } : nil
            )
        } else {
            ErrorNote(message, action: retry)
        }
    }

    private func pointsAtConnection(_ error: APIError) -> Bool {
        switch error {
        case .offline, .timedOut, .serverUnreachable, .unavailable, .server, .unexpectedResponse: return true
        default: return false
        }
    }
}
