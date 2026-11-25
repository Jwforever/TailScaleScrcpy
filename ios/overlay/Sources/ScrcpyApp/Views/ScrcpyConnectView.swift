import SwiftUI
import ScrcpyKit

// MARK: - 设计令牌

private enum Palette {
    static let bg = Color.black
    static let card = Color.white.opacity(0.045)
    static let cardRaised = Color.white.opacity(0.07)
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
}

private let presets: [QualityPreset] = [
    QualityPreset(name: "省流", detail: "720p", resolution: 720, bitrate: 3),
    QualityPreset(name: "均衡", detail: "1080p", resolution: 1280, bitrate: 6),
    QualityPreset(name: "清晰", detail: "1600px", resolution: 1600, bitrate: 12),
    QualityPreset(name: "原画", detail: "2560px", resolution: 2560, bitrate: 20)
]

/// 帧率上限由平板屏幕刷新率决定，超过刷新率的部分会自动被设备限制
private let fpsChoices: [Int] = [30, 60, 90, 120, 144]

// MARK: - 基础组件

private struct MicroLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.8)
            .foregroundColor(Palette.label)
    }
}

private struct FieldBox: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var numeric: Bool = true
    var hint: String? = nil
    /// 右侧附件（如「默认」按钮），与输入框同处一个 HStack，保证严格对齐
    var trailing: AnyView? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            MicroLabel(text: label)
            HStack(spacing: 12) {
                TextField("", text: $text, prompt: Text(placeholder).foregroundColor(.white.opacity(0.20)))
                    .font(.system(size: 19, weight: .light, design: numeric ? .monospaced : .default))
                    .foregroundColor(.white)
                    .keyboardType(numeric ? .numbersAndPunctuation : .URL)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 17)
                    .frame(height: 52)
                    .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Palette.card))
                    .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
                if let trailing = trailing {
                    trailing
                }
            }
            if let hint = hint {
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundColor(Palette.label)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SoftButtonStyle: ButtonStyle {
    var filled: Bool = true
    var height: CGFloat = 52

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(filled ? .black : .white)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                Capsule(style: .continuous)
                    .fill(filled ? Color.white : Palette.cardRaised)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(filled ? Color.clear : Palette.stroke, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.982 : 1)
            .animation(.easeOut(duration: 0.13), value: configuration.isPressed)
    }
}

// MARK: - 主界面（配置）

public struct ScrcpyConnectView: View {
    @ObservedObject public var client: ScrcpyClient
    @StateObject private var vm: DeviceDiscoveryViewModel
    @ObservedObject private var pm = ProfileManager.shared

    @State private var ip: String = ""
    @State private var connectPort: String = "5555"
    @State private var presetIndex: Int = 1
    @State private var fpsIndex: Int = 1
    @State private var showPairing: Bool = false

    public init(client: ScrcpyClient) {
        self.client = client
        _vm = StateObject(wrappedValue: DeviceDiscoveryViewModel(client: client))
    }

    private var isMirroring: Bool { client.state == .mirroring }

    private var isConnecting: Bool {
        if case .connecting = client.state { return true }
        return false
    }

    private var errorText: String? {
        if case .error(let msg) = client.state { return msg }
        return nil
    }

    private var hasPaired: Bool {
        UserDefaults.standard.bool(forKey: "scrcpy_has_paired")
    }

    public var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()

            RadialGradient(
                colors: [Palette.accent.opacity(0.20), Color.clear],
                center: .init(x: 0.5, y: -0.05),
                startRadius: 0,
                endRadius: 560
            )
            .ignoresSafeArea()
            .blur(radius: 30)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    firstRunCard
                    section("01", "设备", content: { deviceBlock })
                    section("02", "画质", content: { qualityBlock })
                    actions
                    statusBar
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 44)
            }
        }
        .onAppear(perform: hydrate)
        .sheet(isPresented: $showPairing) {
            PairingSheet(vm: vm, host: ip)
                .preferredColorScheme(.dark)
        }
    }

    // MARK: 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            MicroLabel(text: "scrcpy · tailscale")
            Text("无线投屏")
                .font(.system(size: 38, weight: .thin))
                .foregroundColor(.white)
            Text("配一次，之后连着端口即可")
                .font(.system(size: 13))
                .foregroundColor(Palette.dim)
        }
    }

    // MARK: 首次使用引导

    private var firstRunCard: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(hasPaired ? "已配对过，可直接连接" : "如果是初次使用，请点击配对")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                Text(hasPaired ? "换了设备或重置过调试密钥，才需要重新配对" : "配对只做一次，之后只需连接")
                    .font(.system(size: 11))
                    .foregroundColor(Palette.label)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button {
                showPairing = true
            } label: {
                Text("配对")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 18)
                    .frame(height: 36)
                    .background(Capsule(style: .continuous).fill(Color.white))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(hasPaired ? Palette.card : Palette.accent.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(hasPaired ? Palette.stroke : Palette.accent.opacity(0.35), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func section<C: View>(_ index: String, _ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Text(index)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(Palette.accent.opacity(0.85))
                Rectangle()
                    .fill(Palette.stroke)
                    .frame(height: 0.5)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .tracking(1.2)
                    .foregroundColor(Palette.label)
            }
            content()
        }
    }

    // MARK: 设备

    private var deviceBlock: some View {
        VStack(spacing: 14) {
            FieldBox(label: "设备地址", placeholder: "100.x.y.z", text: $ip)

            FieldBox(
                label: "连接端口",
                placeholder: "5555",
                text: $connectPort,
                hint: "一般不用改动，保持 5555 即可（默认）",
                trailing: AnyView(
                    Button {
                        connectPort = "5555"
                    } label: {
                        Text("默认")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Palette.dim)
                            .frame(width: 68, height: 52)
                            .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Palette.card))
                            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                )
            )
        }
    }

    // MARK: 画质

    private var qualityBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
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
                                .font(.system(size: 10, design: .monospaced))
                                .opacity(0.55)
                        }
                        .foregroundColor(presetIndex == i ? .black : Palette.dim)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(presetIndex == i ? Color.white : Palette.card)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(presetIndex == i ? Color.clear : Palette.stroke, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            MicroLabel(text: "帧率 fps")

            HStack(spacing: 8) {
                ForEach(fpsChoices.indices, id: \.self) { i in
                    Button {
                        fpsIndex = i
                    } label: {
                        Text("\(fpsChoices[i])")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(fpsIndex == i ? .black : Palette.dim)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(fpsIndex == i ? Color.white : Palette.card)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(fpsIndex == i ? Color.clear : Palette.stroke, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("上限取决于平板屏幕刷新率；链路不稳时建议降到 60。")
                .font(.system(size: 10))
                .foregroundColor(Palette.label)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 连接 / 断开

    private var actions: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    connect()
                } label: {
                    HStack(spacing: 8) {
                        if isConnecting {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.7)
                                .tint(.black)
                        }
                        Text(isConnecting ? "连接中" : (isMirroring ? "已连接" : "连接"))
                    }
                }
                .buttonStyle(SoftButtonStyle(filled: true))
                .disabled(ip.trimmingCharacters(in: .whitespaces).isEmpty || isConnecting || isMirroring)

                Button {
                    disconnect()
                } label: {
                    Text("断开")
                }
                .buttonStyle(SoftButtonStyle(filled: false))
                .frame(width: 108)
                .disabled(!isMirroring && !isConnecting)
            }
        }
        .padding(.top, 2)
    }

    // MARK: 状态

    private var statusBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                Text(statusText)
                    .font(.system(size: 12))
                    .foregroundColor(errorText == nil ? Palette.dim : Color.orange.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text("adb over wifi")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Palette.label)
            }
        }
        .padding(.top, 4)
    }

    private var statusColor: Color {
        if errorText != nil { return Color.orange }
        if isMirroring { return Palette.accent }
        if isConnecting { return Palette.accent.opacity(0.6) }
        return Color.white.opacity(0.22)
    }

    private var statusText: String {
        if let e = errorText { return "连接失败：\(e)" }
        if case .connecting(let step) = client.state { return step }
        if isMirroring { return "已连接 · \(client.deviceName.isEmpty ? "Android" : client.deviceName)" }
        return "未连接"
    }

    // MARK: 行为

    private func hydrate() {
        if ip.isEmpty { ip = pm.activeProfile.host }
        if UInt16(connectPort) == nil { connectPort = "5555" }
    }

    private func connect() {
        var profile = pm.activeProfile
        profile.host = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.port = UInt16(connectPort.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 5555
        let q = presets[presetIndex]
        profile.resolution = q.resolution
        profile.bitrateMbps = q.bitrate
        profile.fps = fpsChoices[fpsIndex]
        profile.audioEnabled = true
        profile.stayAwake = true
        pm.activeProfile = profile
        vm.connectDevice(mode: .mirror)
    }

    private func disconnect() {
        client.stop()
    }
}

// MARK: - 配对二级页

private struct PairingSheet: View {
    @ObservedObject var vm: DeviceDiscoveryViewModel
    let host: String

    @Environment(\.dismiss) private var dismiss
    @State private var pairPort: String = ""
    @State private var pairCode: String = ""

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            MicroLabel(text: "pairing")
                            Text("配对设备")
                                .font(.system(size: 30, weight: .thin))
                                .foregroundColor(.white)
                        }
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white.opacity(0.7))
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(Palette.card))
                        }
                        .buttonStyle(.plain)
                    }

                    Text("平板：设置 → 开发者选项 → 无线调试 → 使用配对码配对设备\n把弹窗里的「端口」和「6 位配对码」填在下面。")
                        .font(.system(size: 12))
                        .foregroundColor(Palette.dim)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 14) {
                        FieldBox(label: "设备地址", placeholder: "100.x.y.z", text: .constant(host.isEmpty ? "未填写" : host))
                            .disabled(true)
                        HStack(spacing: 14) {
                            FieldBox(label: "配对端口", placeholder: "40303", text: $pairPort)
                            FieldBox(label: "配对码", placeholder: "730124", text: $pairCode)
                        }
                    }

                    Button {
                        vm.pairDevice(hostInput: host, portInput: pairPort, codeInput: pairCode)
                    } label: {
                        HStack(spacing: 8) {
                            if vm.isPairing {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .scaleEffect(0.7)
                                    .tint(.black)
                            }
                            Text(vm.isPairing ? "配对中" : "开始配对")
                        }
                    }
                    .buttonStyle(SoftButtonStyle(filled: true))
                    .disabled(vm.isPairing || host.isEmpty || pairPort.isEmpty || pairCode.isEmpty)

                    if let msg = vm.pairStatusMessage {
                        Text(msg)
                            .font(.system(size: 12))
                            .foregroundColor(vm.pairSuccess ? Palette.accent : Color.orange.opacity(0.95))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if vm.pairSuccess {
                        Button {
                            UserDefaults.standard.set(true, forKey: "scrcpy_has_paired")
                            dismiss()
                        } label: {
                            Text("完成，返回")
                        }
                        .buttonStyle(SoftButtonStyle(filled: false))
                    }

                    Text("说明：配对只在第一次需要。配对成功后关掉弹窗回主页点「连接」即可，之后端口保持 5555 一般不用再改。")
                        .font(.system(size: 11))
                        .foregroundColor(Palette.label)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)
                .padding(.top, 30)
                .padding(.bottom, 40)
            }
        }
    }
}
