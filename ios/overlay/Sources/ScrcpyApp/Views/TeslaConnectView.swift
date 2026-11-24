import SwiftUI
import ScrcpyKit

// MARK: - 设计令牌

private enum T {
    static let bg = Color.black
    static let card = Color.white.opacity(0.045)
    static let stroke = Color.white.opacity(0.09)
    static let accent = Color(red: 0.20, green: 0.78, blue: 0.95)
    static let label = Color.white.opacity(0.36)
    static let dim = Color.white.opacity(0.55)
}

private struct QualityPreset {
    let name: String
    let detail: String
    let resolution: Int
    let bitrate: Double
    let fps: Int
}

private let presets: [QualityPreset] = [
    QualityPreset(name: "省流", detail: "720p", resolution: 720, bitrate: 3, fps: 30),
    QualityPreset(name: "均衡", detail: "1080p", resolution: 1280, bitrate: 6, fps: 60),
    QualityPreset(name: "清晰", detail: "1600px", resolution: 1600, bitrate: 12, fps: 60),
    QualityPreset(name: "原画", detail: "2560px", resolution: 2560, bitrate: 20, fps: 60)
]

// MARK: - 组件

private struct MicroLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.8)
            .foregroundColor(T.label)
    }
}

private struct TeslaField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var numeric: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            MicroLabel(text: label)
            TextField("", text: $text, prompt: Text(placeholder).foregroundColor(.white.opacity(0.20)))
                .font(.system(size: 19, weight: .light, design: numeric ? .monospaced : .default))
                .foregroundColor(.white)
                .keyboardType(numeric ? .numbersAndPunctuation : .URL)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                .padding(.vertical, 15)
                .padding(.horizontal, 17)
                .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(T.card))
                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(T.stroke, lineWidth: 1))
        }
    }
}

private struct TeslaButtonStyle: ButtonStyle {
    var filled: Bool = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(filled ? .black : .white)
            .frame(maxWidth: .infinity)
            .frame(height: filled ? 56 : 48)
            .background(
                Capsule(style: .continuous)
                    .fill(filled ? Color.white : Color.white.opacity(0.07))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(filled ? Color.clear : T.stroke, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.982 : 1)
            .animation(.easeOut(duration: 0.13), value: configuration.isPressed)
    }
}

// MARK: - 主界面

public struct TeslaConnectView: View {
    @ObservedObject public var client: ScrcpyClient
    @StateObject private var vm: DeviceDiscoveryViewModel
    @ObservedObject private var pm = ProfileManager.shared

    @State private var ip: String = ""
    @State private var pairPort: String = ""
    @State private var pairCode: String = ""
    @State private var connectPort: String = "5555"
    @State private var presetIndex: Int = 1

    public init(client: ScrcpyClient) {
        self.client = client
        _vm = StateObject(wrappedValue: DeviceDiscoveryViewModel(client: client))
    }

    private var isMirroring: Bool { client.state == .mirroring }

    public var body: some View {
        ZStack {
            T.bg.ignoresSafeArea()

            RadialGradient(
                colors: [T.accent.opacity(0.20), Color.clear],
                center: .init(x: 0.5, y: -0.05),
                startRadius: 0,
                endRadius: 560
            )
            .ignoresSafeArea()
            .blur(radius: 30)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 30) {
                    header
                    section("01", "设备", content: { deviceBlock })
                    section("02", "配对", content: { pairBlock })
                    section("03", "画质", content: { qualityBlock })
                    cta
                    statusBar
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 44)
            }
        }
        .onAppear(perform: hydrate)
    }

    // MARK: 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            MicroLabel(text: "scrcpy · tailscale")
            Text("无线投屏")
                .font(.system(size: 38, weight: .thin, design: .default))
                .foregroundColor(.white)
            Text("配对一次，之后连端口即可")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(T.dim)
        }
    }

    @ViewBuilder
    private func section<C: View>(_ index: String, _ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Text(index)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(T.accent.opacity(0.85))
                Rectangle()
                    .fill(T.stroke)
                    .frame(height: 0.5)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .tracking(1.2)
                    .foregroundColor(T.label)
            }
            content()
        }
    }

    // MARK: 设备

    private var deviceBlock: some View {
        VStack(spacing: 14) {
            TeslaField(label: "设备地址", placeholder: "100.x.y.z", text: $ip)
            HStack(spacing: 14) {
                TeslaField(label: "连接端口", placeholder: "5555", text: $connectPort)
                Button {
                    connectPort = "5555"
                } label: {
                    Text("5555")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(T.dim)
                        .frame(width: 74, height: 50)
                        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(T.card))
                        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(T.stroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.top, 26)
            }
        }
    }

    // MARK: 配对

    private var pairBlock: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                TeslaField(label: "配对端口", placeholder: "40303", text: $pairPort)
                TeslaField(label: "配对码", placeholder: "730124", text: $pairCode)
            }
            Button {
                vm.pairDevice(hostInput: ip, portInput: pairPort, codeInput: pairCode)
            } label: {
                HStack(spacing: 8) {
                    if vm.isPairing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.7)
                            .tint(.white)
                    }
                    Text(vm.isPairing ? "配对中" : "开始配对")
                }
            }
            .buttonStyle(TeslaButtonStyle(filled: false))
            .disabled(vm.isPairing)

            if let msg = vm.pairStatusMessage {
                Text(msg)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(vm.pairSuccess ? T.accent : Color.orange.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("平板：设置 → 开发者选项 → 无线调试 → 使用配对码配对")
                    .font(.system(size: 12))
                    .foregroundColor(T.label)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 画质

    private var qualityBlock: some View {
        HStack(spacing: 8) {
            ForEach(presets.indices, id: \.self) { i in
                let p = presets[i]
                Button {
                    presetIndex = i
                } label: {
                    VStack(spacing: 4) {
                        Text(p.name)
                            .font(.system(size: 13, weight: .medium))
                        Text(p.detail)
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .opacity(0.55)
                    }
                    .foregroundColor(presetIndex == i ? .black : T.dim)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(presetIndex == i ? Color.white : T.card)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(presetIndex == i ? Color.clear : T.stroke, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: 主按钮

    private var cta: some View {
        VStack(spacing: 12) {
            Button {
                connect()
            } label: {
                Text(isMirroring ? "连接中…" : "开始投屏")
            }
            .buttonStyle(TeslaButtonStyle(filled: true))
            .disabled(ip.trimmingCharacters(in: .whitespaces).isEmpty)

            if isMirroring {
                Button {
                    // MirrorSessionView 会自动接管画面，这里只做提示
                } label: {
                    Text("画面已接管")
                }
                .buttonStyle(TeslaButtonStyle(filled: false))
                .disabled(true)
            }
        }
        .padding(.top, 4)
    }

    // MARK: 状态

    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isMirroring ? T.accent : Color.white.opacity(0.22))
                .frame(width: 6, height: 6)
            Text(isMirroring ? "已连接 · \(client.deviceName.isEmpty ? "Android" : client.deviceName)" : "未连接")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(T.dim)
            Spacer()
            Text("adb over wifi")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundColor(T.label)
        }
        .padding(.top, 6)
    }

    // MARK: 行为

    private func hydrate() {
        if ip.isEmpty { ip = pm.activeProfile.host }
        if let p = UInt16(connectPort), p == 0 { connectPort = "5555" }
    }

    private func connect() {
        var profile = pm.activeProfile
        profile.host = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.port = UInt16(connectPort.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 5555
        let q = presets[presetIndex]
        profile.resolution = q.resolution
        profile.bitrateMbps = q.bitrate
        profile.fps = q.fps
        profile.audioEnabled = true
        profile.stayAwake = true
        pm.activeProfile = profile
        vm.connectDevice(mode: .mirror)
    }
}
