import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// A made-up screenshot of a failing build, drawn here: what the toolbar's "Add sample screenshot" attaches, so the
/// demo (and its UI test) can send a picture without Photos.
enum SampleScreenshot {
    @MainActor
    static func png() -> Data? {
        let renderer = ImageRenderer(content: Picture())
        renderer.scale = 2
        guard let image = renderer.cgImage else {
            return nil
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    private struct Picture: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Label("Build failed", systemImage: "xmark.octagon.fill")
                    .font(.headline)
                    .foregroundStyle(.red)
                Text("ChatView.swift:42: cannot find 'composer' in scope")
                    .font(.caption.monospaced())
                ForEach(0..<4, id: \.self) { row in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.gray.opacity(0.25))
                        .frame(width: CGFloat(220 - row * 30), height: 10)
                }
            }
            .padding(20)
            .frame(width: 320, height: 200, alignment: .topLeading)
            .background(.white)
            .environment(\.colorScheme, .light)
        }
    }
}
