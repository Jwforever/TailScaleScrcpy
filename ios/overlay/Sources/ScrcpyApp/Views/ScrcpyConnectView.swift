import SwiftUI
import ScrcpyKit

// MARK: - 浅色设计令牌

private enum Palette {
    static let bg = Color(red: 0.953, green: 0.957, blue: 0.969)
    static let card = Color.white
    static let cardAlt = Color(red: 0.973, green: 0.976, blue: 0.984)
    static let codeBg = Color(red: 0.941, green: 0.945, blue: 0.957)
    static let stroke = Color(red: 0.894, green: 0.906, blue: 0.925)
    static let accent = Color(red: 0.039, green: 0.518, blue: 1.0)
    static let warm = Color(red: 0.85, green: 0.45, blue: 0.10)
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
    @Environment(\.verticalSizeClass) private var vSize

    @State private var ip: String = ""
    @State private var connectPort: String = "5555"
    @State private var presetIndex: Int = 1
    @State private var fpsIndex: Int = 1
    @State private var audioEnabled: Bool = false
    @State private var showGuide: Bool = false

    public init(client: ScrcpyClient) {
        self.client = client
        _vm = StateObject(wrappedValue: DeviceDiscoveryViewModel(client: client))
    }

    private var isMirroring: Bool { client.state == .mirroring }
    private var isLandscape: Bool { vSize == .compact }

    private var isConnecting: Bool {
        if case .connecting = client.state { return true }
        return false
    }

    private var errorText: String? {
        if case .error(let msg) = client.state { return msg }
        return nil
    }

    public var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                if isLandscape {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 12) {
                            header
                            guideBanner
                            deviceSection
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            qualitySection
                            actions
                            statusBar
                        }
                    }
                    .frame(maxWidth: 940)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        guideBanner
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
        }
        .onAppear(perform: hydrate)
        .sheet(isPresented: $showGuide) {
            SetupGuideSheet()
        }
    }

    // MARK: 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("无线投屏")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(Palette.text)
            Text("scrcpy over tailscale · 先开 5555，再连接")
                .font(.system(size: 10))
                .foregroundColor(Palette.dim)
        }
    }

    // MARK: 使用说明入口

    private var guideBanner: some View {
        HStack(spacing: 9) {
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 13))
                .foregroundColor(Palette.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("初次使用？需要先在平板上开启 5555")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Palette.text)
                Text("iOS 端不支持 adb 配对，只能用 5555 明文调试端口")
                    .font(.system(size: 9))
                    .foregroundColor(Palette.dim)
            }
            Spacer(minLength: 4)
            Button {
                showGuide = true
            } label: {
                Text("查看方法")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 11)
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
                .foregroundColor(errorText == nil ? Palette.dim : Palette.warm)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Text("adb over wifi")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Palette.label)
        }
    }

    private var statusColor: Color {
        if errorText != nil { return Palette.warm }
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

// MARK: - 使用说明页

private struct SetupGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var vSize

    private var isLandscape: Bool { vSize == .compact }

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("使用说明")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(Palette.text)
                            Text("为什么不能配对 · 怎么开 5555")
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

                    if isLandscape {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 14) {
                                whyCard
                                rootCard
                            }
                            VStack(alignment: .leading, spacing: 14) {
                                noRootCard
                                restartCard
                                addressCard
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            whyCard
                            rootCard
                            noRootCard
                            restartCard
                            addressCard
                        }
                    }
                }
                .frame(maxWidth: isLandscape ? 960 : .infinity)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
        }
    }

    private var whyCard: some View {
        card(title: "为什么不支持「初次无线配对」", tint: Palette.warm) {
            Text("Android 11 起的「无线调试配对」并不是普通 adb 连接，它用的是独立的 pairing 协议：SPAKE2 密钥交换 + TLS-PSK 加密握手，配对成功才下发证书。\n\n本 App 的 iOS 端只实现了经典 adb 协议（AUTH 用 RSA 公钥签名），没有实现 pairing 握手，所以在手机上无法完成初次配对。\n\n因此必须先在平板侧把 adbd 开成 5555 的明文 TCP 端口，iOS 才能连上去。")
                .font(.system(size: 11))
                .foregroundColor(Palette.dim)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var rootCard: some View {
        card(title: "方案 A · 设备已 root（推荐）", tint: Palette.accent) {
            VStack(alignment: .leading, spacing: 8) {
                Text("在平板上打开带终端的文件管理器（如 MT 管理器 → 终端模拟器），依次执行：")
                    .font(.system(size: 11))
                    .foregroundColor(Palette.dim)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                codeBlock("""
                su
                setprop service.adb.tcp.port 5555
                stop adbd
                start adbd
                """)
                Text("或者一条命令搞定：")
                    .font(.system(size: 11))
                    .foregroundColor(Palette.dim)
                codeBlock("""
                su -c "setprop service.adb.tcp.port 5555"
                su -c "stop adbd; start adbd"
                """)
                Text("执行后 adbd 会以 5555 端口监听，回到本页填地址点「连接」即可。")
                    .font(.system(size: 11))
                    .foregroundColor(Palette.dim)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var noRootCard: some View {
        card(title: "方案 B · 设备未 root（借电脑开）", tint: Palette.accent) {
            VStack(alignment: .leading, spacing: 8) {
                Text("B1. USB 连电脑，在电脑上执行（最简单）")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Palette.text)
                codeBlock("""
                adb devices
                adb tcpip 5555
                adb connect 平板IP:5555
                """)

                Text("B2. 用 scrcpy 一步到位")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Palette.text)
                codeBlock("""
                scrcpy --tcpip=平板IP:5555
                """)

                Text("B3. 电脑做无线配对（Android 11+，不用插线）")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Palette.text)
                Text("平板：设置 → 开发者选项 → 无线调试 → 使用配对码配对设备，记下「IP:配对端口」与 6 位配对码。")
                    .font(.system(size: 11))
                    .foregroundColor(Palette.dim)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                codeBlock("""
                adb pair 平板IP:配对端口
                # 按提示输入 6 位配对码
                adb connect 平板IP:连接端口
                adb tcpip 5555
                """)

                Text("三条路最后都要落到 adb tcpip 5555 —— 这才是把端口固定成 5555 的关键。")
                    .font(.system(size: 11))
                    .foregroundColor(Palette.dim)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var restartCard: some View {
        card(title: "重要 · 设备重启后会失效", tint: Palette.warm) {
            Text("adb tcpip 5555 和 setprop 都只存在于内存里。被控设备一旦重启，5555 端口就没了，App 会报「连接被拒绝」。\n\n重启后需要重新执行一次上面的命令。root 设备可以写进开机脚本或 Magisk 模块自动化。")
                .font(.system(size: 11))
                .foregroundColor(Palette.dim)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var addressCard: some View {
        card(title: "关于「平板IP」", tint: Palette.accent) {
            Text("走 Tailscale 就填 100.x.y.z 的 tailnet 地址（主页会自动带出上次用过的）。\n局域网直连则填平板在 Wi-Fi 里的 192.168.x.x。")
                .font(.system(size: 11))
                .foregroundColor(Palette.dim)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func card<C: View>(title: String, tint: Color, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(tint)
                    .frame(width: 3, height: 12)
                    .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Palette.text)
            }
            content()
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
    }

    private func codeBlock(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(Palette.text)
            .lineSpacing(2)
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.codeBg))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Palette.stroke, lineWidth: 1))
            .textSelection(.enabled)
    }
}
