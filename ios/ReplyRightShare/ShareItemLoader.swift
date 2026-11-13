import Foundation
import ReplyRightCore
import ReplyRightUI
import UIKit
import UniformTypeIdentifiers

/// A screenshot that has already been downsized and re-encoded on the device.
/// The original image is never kept.
struct PreparedShot: Identifiable {
    let id = UUID()
    /// JPEG data, ready to upload if the user asks for replies.
    let data: Data
    /// A small preview for the share sheet.
    let thumbnail: UIImage?
}

/// What the user handed to the share sheet.
struct SharedContent {
    var text: String
    var shots: [PreparedShot]

    var isEmpty: Bool { text.isEmpty && shots.isEmpty }
}

/// Reads the shared items on the device. Nothing here touches the network.
enum ShareItemLoader {
    static func load(from items: [NSExtensionItem]) async -> SharedContent {
        var pieces: [String] = []
        var shots: [PreparedShot] = []

        for item in items {
            var foundText = false
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    guard shots.count < RequestLimits.maxImages else { continue }
                    if let shot = await loadShot(from: provider) {
                        shots.append(shot)
                    }
                } else if let type = textType(for: provider) {
                    if let text = await loadText(from: provider, type: type) {
                        let clean = text.trimmed
                        if !clean.isEmpty, !pieces.contains(clean) {
                            pieces.append(clean)
                            foundText = true
                        }
                    }
                }
            }
            // Some apps put the selected text on the item itself rather than in an attachment.
            if !foundText, let fallback = item.attributedContentText?.string.trimmed,
               !fallback.isEmpty, !pieces.contains(fallback) {
                pieces.append(fallback)
            }
        }

        let text = ConversationText.clampRecent(pieces.joined(separator: "\n"), limit: RequestLimits.conversationChars)
        return SharedContent(text: text, shots: shots)
    }

    // MARK: Screenshots

    private static func loadShot(from provider: NSItemProvider) async -> PreparedShot? {
        await withCheckedContinuation { (continuation: CheckedContinuation<PreparedShot?, Never>) in
            provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { item, _ in
                var prepared: Data?
                if let image = item as? UIImage {
                    prepared = ScreenshotPreparer.prepare(image)
                } else if let data = item as? Data {
                    prepared = ScreenshotPreparer.prepare(data)
                } else if let url = item as? URL, let data = try? Data(contentsOf: url) {
                    prepared = ScreenshotPreparer.prepare(data)
                }
                guard let jpeg = prepared else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: PreparedShot(data: jpeg, thumbnail: makeThumbnail(from: jpeg)))
            }
        }
    }

    static func makeThumbnail(from data: Data, maxEdge: CGFloat = 320) -> UIImage? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        guard longest > maxEdge, longest > 0 else { return image }
        let ratio = maxEdge / longest
        let size = CGSize(width: floor(image.size.width * ratio), height: floor(image.size.height * ratio))
        return image.preparingThumbnail(of: size) ?? image
    }

    // MARK: Text

    private static func textType(for provider: NSItemProvider) -> UTType? {
        let candidates: [UTType] = [.plainText, .text, .fileURL]
        for type in candidates where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            return type
        }
        return nil
    }

    private static func loadText(from provider: NSItemProvider, type: UTType) async -> String? {
        // Raw bytes are only trusted as text when the item is declared as plain text.
        let allowsRawData = type == .plainText
        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, _ in
                continuation.resume(returning: text(from: item, allowsRawData: allowsRawData))
            }
        }
    }

    private static func text(from item: NSSecureCoding?, allowsRawData: Bool) -> String? {
        if let string = item as? String {
            return string
        }
        if let attributed = item as? NSAttributedString {
            return attributed.string
        }
        if allowsRawData, let data = item as? Data {
            return String(data: data, encoding: .utf8)
        }
        if let url = item as? URL, url.isFileURL {
            return try? String(contentsOf: url, encoding: .utf8)
        }
        return nil
    }
}
