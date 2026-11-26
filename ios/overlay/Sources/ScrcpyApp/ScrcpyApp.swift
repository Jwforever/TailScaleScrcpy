import SwiftUI
import ScrcpyKit

#if canImport(AppKit)
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
#endif

public struct RootContentView: View {
    @ObservedObject public var client: ScrcpyClient
    @Environment(\.scenePhase) private var scenePhase

    /// 重连期间保持投屏页可见，避免画面闪回配置页（用户感知为「连接被退出」）
    @State private var holdMirror = false

    public init(client: ScrcpyClient) {
        self.client = client
    }

    private var mirrorVisible: Bool {
        if case .mirroring = client.state { return true }
        return holdMirror
    }

    public var body: some View {
        ZStack {
            ScrcpyConnectView(client: client)
                .opacity(mirrorVisible ? 0 : 1)
                .allowsHitTesting(!mirrorVisible)

            if mirrorVisible {
                MirrorSessionView(client: client)
                    .transition(.opacity)
            }
        }
        #if canImport(UIKit)
        .preferredColorScheme(.dark)
        #endif
        .onChange(of: client.state) { state in
            switch state {
            case .mirroring:
                holdMirror = true
            case .disconnected, .error:
                holdMirror = false
            case .connecting:
                break   // 重连过程中保持画面层
            }
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            guard case .mirroring = client.state else { return }

            // 回到前台：iOS 会掐断后台期间的连接，视频流往往已经死了。
            // 用「1.5 秒内是否收到新帧」判断，未收到则就地重连（画面层保持，不闪回配置页）。
            let framesBefore = client.decoder.frameCount
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard case .mirroring = client.state else { return }
                if client.decoder.frameCount == framesBefore {
                    let savedHost = client.host
                    let savedPort = client.port
                    client.stop()
                    client.host = savedHost
                    client.port = savedPort
                    client.start()
                }
            }
        }
    }
}

@main
public struct ScrcpyApp: App {
    #if canImport(AppKit)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    private let client = ScrcpyClient()

    public init() {}

    public var body: some Scene {
        WindowGroup("Scrcpy iOS Client") {
            RootContentView(client: client)
                #if os(macOS)
                .frame(minWidth: 420, idealWidth: 480, minHeight: 680, idealHeight: 800)
                #endif
        }
    }
}
