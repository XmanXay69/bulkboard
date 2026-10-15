import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Progress photos live as JPEG files next to the database, never inside it.
/// Imports are downscaled and re-encoded, which also drops EXIF metadata such as GPS location.
enum PhotoStore {
    static var directory: URL {
        let dir: URL
        if Persistence.usesInMemoryStore {
            dir = FileManager.default.temporaryDirectory.appendingPathComponent("BulkBoard-Photos-\(ProcessInfo.processInfo.processIdentifier)")
        } else {
            dir = Persistence.appSupportDirectory.appendingPathComponent("Photos", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for filename: String, in folder: URL = directory) -> URL {
        folder.appendingPathComponent(filename)
    }

    /// Saves an image file's contents as a downscaled JPEG and returns the new file name.
    static func save(_ data: Data, maxPixelSize: Int = 1600, in folder: URL = directory) throws -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw PhotoError.unreadable }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw PhotoError.unreadable }
        let filename = "\(UUID().uuidString).jpg"
        let url = url(for: filename, in: folder)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw PhotoError.unwritable
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw PhotoError.unwritable }
        return filename
    }

    static func jpegData(_ filename: String, in folder: URL = directory) -> Data? {
        try? Data(contentsOf: url(for: filename, in: folder))
    }

    static func image(_ filename: String, in folder: URL = directory) -> NSImage? {
        NSImage(contentsOf: url(for: filename, in: folder))
    }

    static func delete(_ filename: String, in folder: URL = directory) {
        try? FileManager.default.removeItem(at: url(for: filename, in: folder))
    }

    /// Asks for an image file.
    static func chooseImage() -> Data? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return try? Data(contentsOf: url)
    }
}

enum PhotoError: LocalizedError {
    case unreadable, unwritable

    var errorDescription: String? {
        switch self {
        case .unreadable: "That file isn't an image BulkBoard can read."
        case .unwritable: "Couldn't save the photo."
        }
    }
}
