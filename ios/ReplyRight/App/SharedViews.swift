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

/// Chooses who a conversation is with. Optional, and always a nickname.
struct PersonPicker: View {
    @Environment(AppModel.self) private var app
    @Binding var selection: CrushProfile?
    @State private var isAdding = false

    var body: some View {
        VStack(alignment: .leading, spacing: RRSpace.s) {
            Eyebrow("Who's this with?")
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
        }
        .sheet(isPresented: $isAdding) {
            PersonEditor(person: nil) { created in
                app.people.insert(created, at: 0)
                selection = created
                app.settings.lastCrushID = created.id
            }
            .preferredColorScheme(app.colorScheme)
        }
    }
}

/// A screen title block: eyebrow, serif headline with one stressed phrase, and a supporting line.
struct ScreenHeader: View {
    var eyebrow: String? = nil
    let lead: String
    let emphasis: String
    var trail: String = ""
    var subtitle: String? = nil
    var style: RRTextStyle = .display

    var body: some View {
        VStack(alignment: .leading, spacing: RRSpace.s) {
            if let eyebrow {
                Eyebrow(eyebrow)
            }
            EditorialTitle(lead, emphasis: emphasis, trail: trail, style: style)
            if let subtitle {
                Text(subtitle)
                    .rrText(.body)
                    .foregroundStyle(Color.rrTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
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
        HStack(spacing: RRSpace.m) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.rrAccent)
                .frame(width: 36, height: 36)
                .background {
                    RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.rrAccentSoft)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .rrText(.headline)
                    .foregroundStyle(Color.rrText)
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
        .padding(.vertical, RRSpace.xs)
        .contentShape(Rectangle())
    }
}

/// The standard scrolling screen: ambient background, generous margins, content from the top.
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
