import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A photo well: drop, paste, choose a file, take one with the Mac's camera, or use an iPhone (Continuity Camera).
struct PhotoInput: View {
    @Binding var photo: Data?
    var height: CGFloat = 200
    var prompt = "Drop a photo, paste one, or take one"

    @State private var isDropTarget = false
    @State private var showCamera = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.surfaceRaised.opacity(0.5))
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isDropTarget ? Theme.accent : Theme.stroke,
                                  style: StrokeStyle(lineWidth: isDropTarget ? 2 : 1, dash: photo == nil ? [5, 4] : []))
                if let data = photo, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: height)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "camera").font(.system(size: 24)).foregroundStyle(Theme.textSecondary)
                        Text(prompt)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                    }
                }
            }
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onDrop(of: [.image, .fileURL], isTargeted: $isDropTarget) { providers in
                load(providers)
                return true
            }
            .onPasteCommand(of: [.image, .fileURL]) { providers in load(providers) }

            HStack(spacing: 6) {
                Button { showCamera = true } label: { Label("Take photo", systemImage: "camera") }
                ContinuityCameraButton { photo = $0 }
                    .frame(width: 32, height: 22)
                    .help("Take a photo with your iPhone (Continuity Camera)")
                Button("Choose…") { if let data = PhotoStore.chooseImage() { photo = data } }
                Spacer(minLength: 0)
                if photo != nil {
                    Button("Remove", role: .destructive) { photo = nil }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .sheet(isPresented: $showCamera) {
            CameraCaptureSheet { photo = $0 }
        }
    }

    private func load(_ providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadDataRepresentation(for: .fileURL) { data, _ in
                guard let data, let url = URL(dataRepresentation: data, relativeTo: nil),
                      let contents = try? Data(contentsOf: url), NSImage(data: contents) != nil else { return }
                Task { @MainActor in photo = contents }
            }
        } else {
            _ = provider.loadDataRepresentation(for: .image) { data, _ in
                guard let data else { return }
                Task { @MainActor in photo = data }
            }
        }
    }
}

/// An iPhone button: opens the system "Import from iPhone" menu (Take Photo, Scan Documents) and
/// receives the picture through the services pasteboard.
struct ContinuityCameraButton: NSViewRepresentable {
    var onImage: (Data) -> Void

    func makeNSView(context: Context) -> ContinuityButton {
        let button = ContinuityButton()
        button.onImage = onImage
        return button
    }

    func updateNSView(_ button: ContinuityButton, context: Context) {
        button.onImage = onImage
    }

    final class ContinuityButton: NSButton, NSServicesMenuRequestor {
        var onImage: ((Data) -> Void)?

        private static let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff, NSPasteboard.PasteboardType(UTType.jpeg.identifier),
                                                                          NSPasteboard.PasteboardType(UTType.heic.identifier)]

        init() {
            super.init(frame: .zero)
            bezelStyle = .push
            controlSize = .small
            image = NSImage(systemSymbolName: "iphone", accessibilityDescription: "Take a photo with your iPhone")
            imagePosition = .imageOnly
            target = self
            action = #selector(showMenu)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override var acceptsFirstResponder: Bool { true }

        @objc private func showMenu() {
            let menu = NSMenu()
            let item = NSMenuItem(title: "Import from iPhone or iPad", action: nil, keyEquivalent: "")
            item.identifier = NSMenuItem.importFromDeviceIdentifier
            menu.addItem(item)
            let hint = NSMenuItem(title: "Your iPhone needs to be nearby, signed in to the same Apple Account.", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(.separator())
            menu.addItem(hint)
            window?.makeFirstResponder(self)
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height + 4), in: self)
        }

        override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?) -> Any? {
            if let returnType, Self.imageTypes.contains(returnType) || NSImage.imageTypes.contains(returnType.rawValue) {
                return self
            }
            return super.validRequestor(forSendType: sendType, returnType: returnType)
        }

        func readSelection(from pasteboard: NSPasteboard) -> Bool {
            for type in Self.imageTypes {
                if let data = pasteboard.data(forType: type) {
                    onImage?(data)
                    return true
                }
            }
            if let image = NSImage(pasteboard: pasteboard), let data = image.tiffRepresentation {
                onImage?(data)
                return true
            }
            return false
        }

        func writeSelection(to pasteboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool { false }
    }
}

/// A thumbnail from the Photos folder, decoded once per file name.
struct StoredPhoto: View {
    var filename: String
    var size: CGFloat
    var cornerRadius: CGFloat = 8

    var body: some View {
        Group {
            if let image = PhotoThumbnails.image(filename) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Theme.surfaceRaised
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

enum PhotoThumbnails {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(_ filename: String) -> NSImage? {
        if let cached = cache.object(forKey: filename as NSString) { return cached }
        guard let image = PhotoStore.image(filename) else { return nil }
        cache.setObject(image, forKey: filename as NSString)
        return image
    }
}
