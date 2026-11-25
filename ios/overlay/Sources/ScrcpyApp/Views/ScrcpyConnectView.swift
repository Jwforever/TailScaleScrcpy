import SwiftUI
import ScrcpyKit

// MARK: - 浅色设计令牌

private enum Palette {
    static let bg = Color(red: 0.953, green: 0.957, blue: 0.969)
    static let card = Color.white
    static let cardAlt = Color(red: 0.973, green: 0.976, blue: 0.984)
    static let stroke = Color(red: 0.894, green: 0.906, blue: 0.925)
    static let accent = Color(red: 0.039, green: 0.518, blue: 1.0)
    static let text = Color(red: 0.067, green: 0.075, blue: 0.094)
    static let dim = Color(red: 0.420, green: 0.451, blue: 0.502)
    static let label = Color(red: 0.604, green: 0.631, blue: 0.675)
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
    QualityPreset(name: "清晰", detail: "1600", resolution: 1600, bitrate: 12),
    QualityPreset(name: "原画", detail: "2560", resolution: 2560, bitrate: 20)
]

private let fpsChoices: [Int] = [30, 60, 90, 120, 144]

// MARK: - 组件

private struct MicroLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .tracking(1.4)
            .foregroundColor(Palette.label)
    }
}

private struct FieldBox: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var numeric: Bool = true
    var trailing: AnyView? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MicroLabel(text: label)
            HStack(spacing: 8) {
                TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Palette.label.opacity(0.55)))
                    .font(.system(size: 16, weight: .regular, design: numeric ? .monospaced : .default))
                    .foregroundColor(Palette.text)
                    .keyboardType(numeric ? .numbersAndPunctuation : .URL)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.cardAlt))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
                if let trailing = trailing {
                    trailing
                }
            }
        }
    }
}

private struct SoftButtonStyle: ButtonStyle {
    var filled: Bool = true
    var height: CGFloat = 46

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(filled ? .white : Palette.text)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(filled ? Palette.accent : Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(filled ? Color.clear : Palette.stroke, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - 配置页

public struct ScrcpyConnectView: View {
    @ObservedObject public var client: ScrcpyClient
    @StateObject private var vm: DeviceDiscoveryViewModel
    @ObservedObject private var pm = ProfileManager.shared

    @State private var ip: String = ""
    @State private var connectPort: String = "5555"
    @State private var presetIndex: Int = 1
    @State private var fpsIndex: Int = 1
    @State private var audioEnabled: Bool = false
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

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    pairBanner
                    deviceSection
                    qualitySection
                    actions
                    statusBar
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 18)
            }
        }
        .onAppear(perform: hydrate)
        .sheet(isPresented: $showPairing) {
            PairingSheet(vm: vm, host: ip)
        }
    }

    // MARK: 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("无线投屏")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(Palette.text)
            Text("scrcpy over tailscale · 配一次，之后连端口即可")
                .font(.system(size: 10))
                .foregroundColor(Palette.dim)
        }
    }

    // MARK: 首次使用

    private var pairBanner: some View {
        HStack(spacing: 9) {
            Image(systemName: hasPaired ? "checkmark.circle.fill" : "info.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(Palette.accent)
            Text(hasPaired ? "已配对，可直接连接" : "如果是初次使用，请点击配对")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Palette.text)
            Spacer(minLength: 4)
            Button {
                showPairing = true
            } label: {
                Text("配对")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 13)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.accent))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Palette.accent.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Palette.accent.opacity(0.18), lineWidth: 1))
    }

    // MARK: 设备

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionTitle("设备")
            FieldBox(label: "设备地址", placeholder: "100.x.y.z", text: $ip)
            FieldBox(
                label: "连接端口",
                placeholder: "5555",
                text: $connectPort,
                trailing: AnyView(
                    Button {
                        connectPort = "5555"
                    } label: {
                        Text("默认 5555")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Palette.dim)
                            .padding(.horizontal, 11)
                            .frame(height: 44)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.card))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                )
            )
            Text("端口一般不用改动，保持 5555 即可")
                .font(.system(size: 9))
                .foregroundColor(Palette.label)
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
    }

    // MARK: 画质

    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionTitle("画质")

            HStack(spacing: 6) {
                ForEach(presets.indices, id: \.self) { i in
                    let p = presets[i]
                    Button {
                        presetIndex = i
                    } label: {
                        VStack(spacing: 1) {
                            Text(p.name)
                                .font(.system(size: 12, weight: .medium))
                            Text(p.detail)
                                .font(.system(size: 9, design: .monospaced))
                                .opacity(0.65)
                        }
                        .foregroundColor(presetIndex == i ? .white : Palette.dim)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(presetIndex == i ? Palette.accent : Palette.cardAlt)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                MicroLabel(text: "帧率")
                Spacer()
                HStack(spacing: 5) {
                    ForEach(fpsChoices.indices, id: \.self) { i in
                        Button {
                            fpsIndex = i
                        } label: {
                            Text("\(fpsChoices[i])")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(fpsIndex == i ? .white : Palette.dim)
                                .frame(width: 40, height: 30)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(fpsIndex == i ? Palette.accent : Palette.cardAlt)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 8) {
                MicroLabel(text: "音频转发")
                Text("未压缩 PCM，约 1.5 Mbps")
                    .font(.system(size: 9))
                    .foregroundColor(Palette.label)
                Spacer()
                Button {
                    audioEnabled.toggle()
                } label: {
                    Text(audioEnabled ? "开" : "关")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(audioEnabled ? .white : Palette.dim)
                        .frame(width: 46, height: 28)
                        .background(
                            Capsule(style: .continuous)
                                .fill(audioEnabled ? Palette.accent : Palette.cardAlt)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
    }

    // MARK: 连接 / 断开

    private var actions: some View {
        HStack(spacing: 9) {
            Button {
                connect()
            } label: {
                HStack(spacing: 6) {
                    if isConnecting {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.6)
                            .tint(.white)
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
            .frame(width: 86)
            .disabled(!isMirroring && !isConnecting)
        }
    }

    // MARK: 状态

    private var statusBar: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 5, height: 5)
            Text(statusText)
                .font(.system(size: 10))
                .foregroundColor(errorText == nil ? Palette.dim : Color(red: 0.85, green: 0.35, blue: 0.10))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Text("adb over wifi")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Palette.label)
        }
    }

    private var statusColor: Color {
        if errorText != nil { return Color(red: 0.90, green: 0.45, blue: 0.13) }
        if isMirroring { return Color(red: 0.20, green: 0.70, blue: 0.35) }
        if isConnecting { return Palette.accent.opacity(0.6) }
        return Palette.label
    }

    private var statusText: String {
        if let e = errorText { return "连接失败：\(e)" }
        if case .connecting(let step) = client.state { return step }
        if isMirroring { return "已连接 · \(client.deviceName.isEmpty ? "Android" : client.deviceName)" }
        return "未连接"
    }

    private func sectionTitle(_ text: String) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Palette.text)
            Rectangle()
                .fill(Palette.stroke)
                .frame(height: 0.5)
        }
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
        profile.audioEnabled = audioEnabled
        profile.stayAwake = true
        pm.activeProfile = profile
        vm.connectDevice(mode: .mirror)
    }

    private func disconnect() {
        client.stop()
    }
}

// MARK: - 配对二级页（浅色）

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
                VStack(alignment: .leading, spacing: 13) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("配对设备")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(Palette.text)
                            Text("只需在初次使用时做一次")
                                .font(.system(size: 10))
                                .foregroundColor(Palette.dim)
                        }
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Palette.dim)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(Palette.card))
                                .overlay(Circle().stroke(Palette.stroke, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text("平板操作路径")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Palette.text)
                        Text("设置 → 开发者选项 → 无线调试 → 使用配对码配对设备\n把弹窗里的「端口」和「6 位配对码」填到下面")
                            .font(.system(size: 11))
                            .foregroundColor(Palette.dim)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Palette.card))

                    VStack(alignment: .leading, spacing: 6) {
                        MicroLabel(text: "设备地址")
                        Text(host.isEmpty ? "（请先在主页填写设备地址）" : host)
                            .font(.system(size: 15, design: .monospaced))
                            .foregroundColor(host.isEmpty ? Palette.label : Palette.text)
                            .padding(.horizontal, 14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 44)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.cardAlt))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
                    }

                    HStack(spacing: 8) {
                        FieldBox(label: "配对端口", placeholder: "40303", text: $pairPort)
                        FieldBox(label: "配对码", placeholder: "730124", text: $pairCode)
                    }

                    Button {
                        vm.pairDevice(hostInput: host, portInput: pairPort, codeInput: pairCode)
                    } label: {
                        HStack(spacing: 6) {
                            if vm.isPairing {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .scaleEffect(0.6)
                                    .tint(.white)
                            }
                            Text(vm.isPairing ? "配对中" : "开始配对")
                        }
                    }
                    .buttonStyle(SoftButtonStyle(filled: true))
                    .disabled(vm.isPairing || host.isEmpty || pairPort.isEmpty || pairCode.isEmpty)

                    if let msg = vm.pairStatusMessage {
                        Text(msg)
                            .font(.system(size: 11))
                            .foregroundColor(vm.pairSuccess ? Palette.accent : Color(red: 0.85, green: 0.35, blue: 0.10))
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

                    Text("配对成功后关掉本页，回主页点「连接」即可；之后端口保持 5555，一般不用再改。")
                        .font(.system(size: 10))
                        .foregroundColor(Palette.label)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 22)
            }
        }
    }
}
