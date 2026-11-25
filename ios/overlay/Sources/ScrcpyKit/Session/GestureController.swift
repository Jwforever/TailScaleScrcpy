import SwiftUI
#if canImport(UIKit)
import UIKit
import AVFoundation

public final class TouchOverlayView: UIView {
    public weak var session: ScrcpyClient?

    /// 单击（非拖动）时回调，用于切换 HUD。不会影响向设备注入的点击。
    public var onSingleTap: (() -> Void)?

    private var activeTouches = [UITouch: UInt64]()
    private var nextPointerId: UInt64 = 0

    /// 每个触摸的起点、按下时刻、最大位移，用于区分「点击」与「拖动」
    private struct TouchMeta {
        var start: CGPoint
        var time: TimeInterval
        var maxMove: CGFloat
    }
    private var touchMeta = [UITouch: TouchMeta]()

    private var now: TimeInterval { Date().timeIntervalSinceReferenceDate }

    /// 挂到窗口后，关闭所有上层手势（SwiftUI 的 onTapGesture 等）的 cancelsTouchesInView。
    /// 默认 true 时，一次单击会被上层手势认领并取消子视图触摸，安卓端只能收到
    /// down+cancel，表现为「能滑动、点不动」。这里从根上关掉取消行为。
    public override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        var node: UIView? = superview
        while let cur = node {
            cur.gestureRecognizers?.forEach { $0.cancelsTouchesInView = false }
            node = cur.superview
        }
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
    }

    private func sendTouchEvent(for touch: UITouch, action: AndroidMotionEventAction) {
        guard let session = session, let videoSize = session.videoDimensions else { return }

        // Find or assign pointerId
        let pointerId: UInt64
        if let existing = activeTouches[touch] {
            pointerId = existing
        } else {
            pointerId = nextPointerId
            nextPointerId = (nextPointerId + 1) % 10
            activeTouches[touch] = pointerId
        }

        let loc = touch.location(in: self)
        let rect = AVMakeRect(aspectRatio: videoSize, insideRect: bounds)
        guard rect.width > 0 && rect.height > 0 else { return }

        // Clamp to video display rect
        let clampedX = max(rect.origin.x, min(rect.origin.x + rect.width, loc.x))
        let clampedY = max(rect.origin.y, min(rect.origin.y + rect.height, loc.y))

        let normX = (clampedX - rect.origin.x) / rect.width
        let normY = (clampedY - rect.origin.y) / rect.height

        let devX = Int32(normX * Double(videoSize.width))
        let devY = Int32(normY * Double(videoSize.height))

        let pressure = Float(touch.force > 0 ? touch.force / touch.maximumPossibleForce : 1.0)

        session.send(controlMessage: .injectTouchEvent(
            action: action,
            pointerId: pointerId,
            x: devX,
            y: devY,
            screenWidth: UInt16(videoSize.width),
            screenHeight: UInt16(videoSize.height),
            pressure: pressure
        ))

        if action == .up || action == .cancel {
            activeTouches.removeValue(forKey: touch)
        }
    }

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            touchMeta[touch] = TouchMeta(start: touch.location(in: self), time: now, maxMove: 0)
            sendTouchEvent(for: touch, action: .down)
        }
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if var m = touchMeta[touch] {
                let p = touch.location(in: self)
                let dx = p.x - m.start.x
                let dy = p.y - m.start.y
                m.maxMove = max(m.maxMove, sqrt(dx * dx + dy * dy))
                touchMeta[touch] = m
            }
            sendTouchEvent(for: touch, action: .move)
        }
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let meta = touchMeta.removeValue(forKey: touch)
            sendTouchEvent(for: touch, action: .up)
            if let m = meta, m.maxMove < 12, now - m.time < 0.40 {
                onSingleTap?()
            }
        }
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let meta = touchMeta.removeValue(forKey: touch)
            // SwiftUI 上层手势（如整屏 onTapGesture）会取消子视图的触摸。
            // 若这次触摸本质上是「点击」，直接取消会让安卓只收到 down+cancel，
            // 表现为「点不动、但能滑动」。因此这里补发 up，让点击成立。
            if let m = meta, m.maxMove < 12, now - m.time < 0.40 {
                sendTouchEvent(for: touch, action: .up)
            } else {
                sendTouchEvent(for: touch, action: .cancel)
            }
        }
    }
}

public struct TouchOverlayRepresentable: UIViewRepresentable {
    @ObservedObject public var session: ScrcpyClient
    public var onSingleTap: (() -> Void)?

    public init(session: ScrcpyClient, onSingleTap: (() -> Void)? = nil) {
        self.session = session
        self.onSingleTap = onSingleTap
    }

    public func makeUIView(context: Context) -> TouchOverlayView {
        let view = TouchOverlayView()
        view.session = session
        view.onSingleTap = onSingleTap
        return view
    }

    public func updateUIView(_ uiView: TouchOverlayView, context: Context) {
        uiView.session = session
        uiView.onSingleTap = onSingleTap
    }
}
#endif
