import AVFoundation
import CoreGraphics
import CoreVideo

/// A made-up ten-second video, written here: what the video fixture's "Add sample video" attaches, so the demo (and
/// its UI tests) can send a video without Photos (jai/agentchatkit#4).
enum SampleVideo {
    static let seconds = 10
    private static let width = 320, height = 200
    private static let framesPerSecond: Int32 = 10

    /// The video's file, written once per launch of the app's temporary folder.
    static func url() async -> URL? {
        let folder = FileManager.default.temporaryDirectory
        let url = folder.appending(path: "agentchat-demo-sample.mov")
        if FileManager.default.fileExists(atPath: url.path()) {
            return url
        }
        let staging = folder.appending(path: "agentchat-demo-sample-\(UUID().uuidString).mov")
        guard await write(to: staging) else {
            return nil
        }
        try? FileManager.default.moveItem(at: staging, to: url)
        return FileManager.default.fileExists(atPath: url.path()) ? url : nil
    }

    private static func write(to url: URL) async -> Bool {
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else {
            return false
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        guard writer.canAdd(input) else {
            return false
        }
        writer.add(input)
        guard writer.startWriting() else {
            return false
        }
        writer.startSession(atSourceTime: .zero)
        let frames = seconds * Int(framesPerSecond)
        for frame in 0..<frames {
            while !input.isReadyForMoreMediaData {
                try? await Task.sleep(for: .milliseconds(5))
            }
            guard let buffer = buffer(frame: frame, of: frames, pool: adaptor.pixelBufferPool) else {
                writer.cancelWriting()
                return false
            }
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: framesPerSecond))
        }
        input.markAsFinished()
        await writer.finishWriting()
        return writer.status == .completed
    }

    /// One frame: a slowly changing colour and a bar that fills as the video plays.
    private static func buffer(frame: Int, of frames: Int, pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        guard let pool else {
            return nil
        }
        var made: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made)
        guard let buffer = made else {
            return nil
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }
        let progress = CGFloat(frame) / CGFloat(max(1, frames - 1))
        context.setFillColor(CGColor(red: 0.15, green: 0.3 + 0.4 * progress, blue: 0.75 - 0.4 * progress, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(gray: 1, alpha: 0.9))
        context.fill(CGRect(x: 20, y: 20, width: (CGFloat(width) - 40) * progress, height: 16))
        return buffer
    }
}
