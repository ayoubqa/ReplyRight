import PhotosUI
import ReplyRightCore
import ReplyRightUI
import SwiftUI
import UIKit

/// Step one: show ReplyRight the conversation. Screenshots, pasted text, or both.
/// Nothing is sent until "Read the conversation" is tapped.
struct ConversationInputView: View {
    @Environment(AppModel.self) private var app
    @State private var pickedPhotos: [PhotosPickerItem] = []

    var body: some View {
        @Bindable var compose = app.compose

        ScreenScroll {
            ScreenHeader(
                lead: "Show me what they said",
                emphasis: "",
                subtitle: "A screenshot is easiest. A few messages before the last one help me get the context."
            )

            ConnectionNotice()

            screenshots

            VStack(alignment: .leading, spacing: RRSpace.s) {
                HStack {
                    Eyebrow(compose.shots.isEmpty ? "Or paste it" : "Anything to add?")
                    Spacer()
                    Button {
                        pasteFromClipboard()
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.rrSecondaryCompact)
                    .accessibilityIdentifier("input-paste")
                }
                RRTextArea(
                    text: $compose.text,
                    placeholder: "Them: so are we still on for friday?\nMe: unless you've found someone better\nThem: still deciding",
                    minHeight: compose.shots.isEmpty ? 150 : 90
                )
                .accessibilityIdentifier("input-text")
                Text("Tip: start lines with \u{201C}Them:\u{201D} and \u{201C}Me:\u{201D} so I know who said what.")
                    .rrText(.caption)
                    .foregroundStyle(Color.rrTextTertiary)
            }

            PersonPicker(selection: $compose.crush)

            Label("Sent only when you tap the button below. Screenshots are read once and never stored.", systemImage: "lock")
                .rrText(.footnote)
                .foregroundStyle(Color.rrTextTertiary)
        }
        .safeAreaInset(edge: .bottom) {
            Button("Read the conversation") {
                Haptics.tap()
                app.homePath.append(.understanding)
                app.compose.startAnalysis(app: app)
            }
            .buttonStyle(.rrPrimary)
            .disabled(!compose.hasInput || compose.isPreparingImages)
            .padding(.horizontal, RRSpace.screen)
            .padding(.vertical, RRSpace.s)
            .background(Color.rrBackground)
            .overlay(alignment: .top) { Rule() }
            .accessibilityIdentifier("input-read")
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onChange(of: pickedPhotos) { _, items in
            guard !items.isEmpty else { return }
            Task { await loadPhotos(items) }
        }
    }

    // MARK: Screenshots

    @ViewBuilder
    private var screenshots: some View {
        let compose = app.compose
        VStack(alignment: .leading, spacing: RRSpace.s) {
            Eyebrow("Screenshots")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: RRSpace.s) {
                    ForEach(Array(compose.shots.enumerated()), id: \.element.id) { index, shot in
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: shot.preview)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 104, height: 168)
                                .clipShape(RoundedRectangle(cornerRadius: RRRadius.control, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: RRRadius.control, style: .continuous)
                                        .strokeBorder(Color.rrLine, lineWidth: 1)
                                }
                                .accessibilityLabel("Screenshot \(index + 1)")
                            Button {
                                withAnimation(.rrSnappy) {
                                    compose.removeShot(shot.id)
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Color.white)
                                    .frame(width: 26, height: 26)
                                    .background(Circle().fill(Color.black.opacity(0.65)))
                            }
                            .padding(6)
                            .accessibilityLabel("Remove screenshot \(index + 1)")
                        }
                    }

                    if compose.canAddShots {
                        PhotosPicker(
                            selection: $pickedPhotos,
                            maxSelectionCount: RequestLimits.maxImages - compose.shots.count,
                            matching: .images
                        ) {
                            VStack(spacing: RRSpace.xs) {
                                if compose.isPreparingImages {
                                    ProgressView()
                                } else {
                                    Image(systemName: "plus")
                                        .font(.system(size: 20, weight: .medium))
                                }
                                Text(compose.shots.isEmpty ? "Add a screenshot" : "Add another")
                                    .rrText(.footnote)
                            }
                            .foregroundStyle(Color.rrTextSecondary)
                            .frame(width: compose.shots.isEmpty ? 168 : 104, height: 168)
                            .overlay {
                                RoundedRectangle(cornerRadius: RRRadius.control, style: .continuous)
                                    .strokeBorder(Color.rrLineStrong, style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                            }
                            .contentShape(RoundedRectangle(cornerRadius: RRRadius.control, style: .continuous))
                        }
                        .buttonStyle(.rrPress)
                    }
                }
                .padding(.horizontal, RRSpace.screen)
            }
            .padding(.horizontal, -RRSpace.screen)

            if let notice = compose.inputNotice {
                Text(notice)
                    .rrText(.footnote)
                    .foregroundStyle(Color.rrWarning)
            }
        }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        var loaded: [Data] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                loaded.append(data)
            }
        }
        pickedPhotos = []
        await app.compose.addImages(loaded)
    }

    /// Reads the clipboard only because the user tapped Paste.
    private func pasteFromClipboard() {
        guard let copied = UIPasteboard.general.string?.trimmed, !copied.isEmpty else {
            app.toast = "There's no text on your clipboard yet."
            return
        }
        let current = app.compose.text.trimmed
        app.compose.text = current.isEmpty ? copied : current + "\n" + copied
        Haptics.tap()
    }
}
