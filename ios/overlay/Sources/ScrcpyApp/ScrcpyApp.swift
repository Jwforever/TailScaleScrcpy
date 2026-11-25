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

    public init(client: ScrcpyClient) {
        self.client = client
    }

    public var body: some View {
        ZStack {
            ScrcpyConnectView(client: client)
                .opacity(client.state == .mirroring ? 0 : 1)
                .allowsHitTesting(client.state != .mirroring)

            if client.state == .mirroring {
                MirrorSessionView(client: client)
                    .transition(.opacity)
            }
        }
        #if canImport(UIKit)
        .preferredColorScheme(.dark)
        #endif
        .onChange(of: scenePhase) { phase in
            // 回到前台：adb 单连接上会积压后台期间的视频数据，
            // 先把陈旧帧丢掉，让控制消息的通道尽快恢复
            if phase == .active {
                client.handleForeground()
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
