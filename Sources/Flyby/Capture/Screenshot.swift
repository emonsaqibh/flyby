import AppKit
import ImageIO
import UniformTypeIdentifiers
import os
import FlybyCore

private let captureLog = Logger(subsystem: "com.fringecore.flyby", category: "capture")

/// A screenshot waiting in the input, or asked about in this session.
///
/// Two sizes of the same picture: `upload`, what the provider sees — a JPEG
/// no longer than `uploadEdge` on its long side, sharp enough to read text in
/// a Retina window without sending megabytes — and the attachment's
/// thumbnail, which is all a chat keeps once it's in history.
struct Screenshot: Identifiable, Equatable {
    static let uploadEdge: CGFloat = 2048
    static let thumbnailEdge: CGFloat = 480

    let attachment: Attachment
    let upload: Data
    let pixelSize: CGSize

    var id: UUID { attachment.id }
    var title: String { attachment.title }
    let mimeType = "image/jpeg"

    var chatImage: ChatImage { ChatImage(data: upload, mimeType: mimeType) }

    static func == (a: Screenshot, b: Screenshot) -> Bool { a.id == b.id }

    init?(image: CGImage, title: String) {
        guard let upload = Self.jpeg(image, longEdge: Self.uploadEdge, quality: 0.88),
              let thumbnail = Self.jpeg(image, longEdge: Self.thumbnailEdge, quality: 0.75) else {
            captureLog.error("Couldn't encode the screenshot")
            return nil
        }
        self.attachment = Attachment(title: title, thumbnail: thumbnail)
        self.upload = upload
        self.pixelSize = CGSize(width: image.width, height: image.height)
    }

    /// Dev builds' `-FlybyDebugImage`: a picture from disk standing in for a
    /// capture.
    init?(contentsOf url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        self.init(image: image, title: url.lastPathComponent)
    }

    // MARK: - For Google's page

    /// Where AI Mode's page is handed the picture from: the page's file
    /// picker only takes files. Written on first use, and gone with the rest
    /// of `directory` when the chat is.
    func file() throws -> URL {
        let url = Self.directory.appendingPathComponent("Screenshot \(id.uuidString.prefix(8)).jpg")
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try upload.write(to: url, options: .atomic)
        }
        return url
    }

    static let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("Screenshots", isDirectory: true)

    /// Nothing of a screenshot outlives its chat on disk.
    static func removeFiles() {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Encoding

    private static func jpeg(_ image: CGImage, longEdge: CGFloat, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        let scaled = scaledDown(image, toLongEdge: longEdge) ?? image
        CGImageDestinationAddImage(destination, scaled, [
            kCGImageDestinationLossyCompressionQuality: quality,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// `nil` when it's small enough already.
    private static func scaledDown(_ image: CGImage, toLongEdge edge: CGFloat) -> CGImage? {
        let long = CGFloat(max(image.width, image.height))
        guard long > edge else { return nil }
        let scale = edge / long
        let width = Int((CGFloat(image.width) * scale).rounded())
        let height = Int((CGFloat(image.height) * scale).rounded())
        // sRGB, which is what a JPEG without a profile is read as; the
        // capture's own display space would need its profile carried along.
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
