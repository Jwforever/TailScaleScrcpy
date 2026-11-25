import SwiftUI
import AVFoundation
#if canImport(UIKit)
import UIKit

public final class UIVideoSampleBufferView: UIView {
    public override class var layerClass: AnyClass {
        return AVSampleBufferDisplayLayer.self
    }

    public var sampleBufferDisplayLayer: AVSampleBufferDisplayLayer {
        return layer as! AVSampleBufferDisplayLayer
    }

    public var videoSize: CGSize = .zero

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayer()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
    }

    private func setupLayer() {
        sampleBufferDisplayLayer.videoGravity = .resizeAspect
        backgroundColor = .black
    }

    public func enqueue(_ sampleBuffer: CMSampleBuffer) {
        // 系统在 App 挂起/被中断后会把渲染层置为「需要 flush 才能继续解码」，
        // 此时 enqueue 的帧会被静默丢弃 —— 表现为切回前台黑屏且一直不恢复。
        if #available(iOS 14.0, tvOS 14.0, macOS 11.0, *) {
            if sampleBufferDisplayLayer.requiresFlushToResumeDecoding {
                sampleBufferDisplayLayer.flush()
            }
        }
        if sampleBufferDisplayLayer.status == .failed {
            sampleBufferDisplayLayer.flush()
        }
        sampleBufferDisplayLayer.enqueue(sampleBuffer)
    }

    /// Computes the exact sub-rect in view coordinates where the video frame is drawn
    public func videoDisplayRect() -> CGRect {
        guard videoSize.width > 0 && videoSize.height > 0 else { return bounds }
        return AVMakeRect(aspectRatio: videoSize, insideRect: bounds)
    }

    /// Converts a point in view coordinates to Android device pixel coordinates (0..<width, 0..<height)
    public func convertToDeviceCoordinates(point: CGPoint) -> CGPoint? {
        let rect = videoDisplayRect()
        guard rect.contains(point) else { return nil }

        let normalizedX = (point.x - rect.origin.x) / rect.size.width
        let normalizedY = (point.y - rect.origin.y) / rect.size.height

        let devX = normalizedX * videoSize.width
        let devY = normalizedY * videoSize.height
        return CGPoint(x: devX, y: devY)
    }
}

public struct ScrcpyVideoView: UIViewRepresentable {
    @ObservedObject public var session: ScrcpyClient

    public init(session: ScrcpyClient) {
        self.session = session
    }

    public func makeUIView(context: Context) -> UIVideoSampleBufferView {
        let view = UIVideoSampleBufferView()
        context.coordinator.setup(view: view, session: session)
        return view
    }

    public func updateUIView(_ uiView: UIVideoSampleBufferView, context: Context) {
        if let size = session.videoDimensions {
            uiView.videoSize = size
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public final class Coordinator: NSObject {
        private var observationTask: Task<Void, Never>?

        func setup(view: UIVideoSampleBufferView, session: ScrcpyClient) {
            // AVSampleBufferDisplayLayer.enqueue 本身线程安全，直接投递即可。
            // 原来每帧都 DispatchQueue.main.async 跳主线程，主线程任何一次布局/重算
            // 都会让这一帧排队，表现为画面抖动与延迟累积。
            session.decoder.onSampleBufferDecoded = { [weak view] sampleBuffer in
                view?.enqueue(sampleBuffer)
            }
        }
    }
}
#elseif canImport(AppKit)
import AppKit

public final class NSVideoSampleBufferView: NSView {
    public let sampleBufferDisplayLayer = AVSampleBufferDisplayLayer()
    public var videoSize: CGSize = .zero

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = sampleBufferDisplayLayer
        sampleBufferDisplayLayer.videoGravity = .resizeAspect
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer = sampleBufferDisplayLayer
        sampleBufferDisplayLayer.videoGravity = .resizeAspect
    }

    public func enqueue(_ sampleBuffer: CMSampleBuffer) {
        sampleBufferDisplayLayer.enqueue(sampleBuffer)
    }
}

public struct ScrcpyVideoView: NSViewRepresentable {
    @ObservedObject public var session: ScrcpyClient

    public init(session: ScrcpyClient) {
        self.session = session
    }

    public func makeNSView(context: Context) -> NSVideoSampleBufferView {
        let view = NSVideoSampleBufferView()
        session.decoder.onSampleBufferDecoded = { [weak view] sampleBuffer in
            DispatchQueue.main.async { [weak view] in
                view?.enqueue(sampleBuffer)
            }
        }
        return view
    }

    public func updateNSView(_ nsView: NSVideoSampleBufferView, context: Context) {
        if let size = session.videoDimensions {
            nsView.videoSize = size
        }
    }
}
#endif
