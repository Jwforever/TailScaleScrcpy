# 投屏助手 · scrcpy + Tailscale

一个 Windows 下的 **scrcpy 图形化启动器**：把手机／平板通过 Tailscale 组网后，无线投屏到电脑。
打包成**单个 exe**，拷到任何 Windows 机器上双击即用，不需要安装 Python、PowerShell 模块或 scrcpy。

[scrcpy](https://github.com/Genymobile/scrcpy) 负责画面采集与传输，[Tailscale](https://tailscale.com/) 负责把设备放进同一个虚拟局域网 —— 这样即使手机在 4G、电脑在公司 Wi-Fi，也能像同一局域网一样连上。

> 本项目只是一个图形壳 + 打包脚本，核心能力来自 scrcpy 和 adb。与 Genymobile / Tailscale 官方无关。

---

## 功能

- **单文件分发**：一个 6 MB 的 exe，内含 scrcpy 全套运行时，首次运行自解包到同级目录
- **自动发现设备**：读取 `tailscale status`，列出 tailnet 内所有 Android 设备
- **无线配对**：图形化完成 Android 11+ 的「无线调试 → 配对码」流程，无需数据线
- **一键固定端口**：连接成功后自动执行 `adb tcpip 5555` 并回连，省去每次查随机端口
- **画质预设**：省流 / 均衡 / 清晰 / 原画，也支持手填尺寸、码率、帧率
- **可切换 scrcpy**：随时指定任意位置的 `scrcpy.exe`（会自动带出同目录的 adb）
- **异常驻留**：scrcpy 出错时控制台窗口不会一闪而过，会停住显示错误码和原因

## 界面

深色控制台 + 圆角卡片布局，主操作按钮为填充式强调色。日志区为纯黑底白字，异常行带 `[!]` 前缀。

## 快速开始

### 用现成的 exe

1. 从 [Releases](../../releases) 下载 `投屏助手.exe`
2. 放到一个**可写目录**（桌面、文档、D 盘都行，不要放 `Program Files`）
3. 双击运行，首次启动会释放 `scrcpy\` 文件夹
4. 电脑和平板都装好 Tailscale 并登录同一账号
5. 点「刷新」选中设备 → 填端口 → 点「连接」→ 点「开始投屏」

> 首次运行可能触发 SmartScreen 蓝色提示（exe 无代码签名），点「更多信息 → 仍要运行」。

### 平板端准备

1. 设置 → 关于平板 → 连点版本号，开启开发者选项
2. 开发者选项 → **无线调试** → 打开
3. 首次配对：点「使用配对码配对设备」，把端口和 6 位码填进程序的「配对」弹窗
4. 配对成功后，把无线调试主页显示的「IP 地址和端口」中的**端口**填到主界面，点「连接」

连接成功后程序会自动把端口固定为 `5555`。

## 自行构建

需要：Windows 10/11、PowerShell 5.1、Python 3（生成图标用）、一份 [scrcpy](https://github.com/Genymobile/scrcpy/releases) 解压目录。

```powershell
# 1. 安装打包模块
Install-Module ps2exe -Scope CurrentUser

# 2. 生成图标（可选，仓库不含 ico 二进制）
python src/make_icon.py

# 3. 打包
powershell -ExecutionPolicy Bypass -File build/build.ps1 -ScrcpyDir "D:\scrcpy\scrcpy-win64-v2.4"
```

产物为 `dist/投屏助手.exe`，已把 scrcpy 以 zip 形式追加在 exe 尾部。

### 原理

```
投屏助手.exe = 主程序(ps2exe 打包的 ps1) + scrcpy.zip + 12 字节页脚
页脚 = "TSZP" + int64(payload 长度)
```

启动时脚本读取自身文件，按页脚定位切片、解压到 `./scrcpy/`，并写入 `.payload` 标记（长度比对）避免重复解包。
这样做是因为 ps2exe 自带的 `-EmbedFiles` 不会覆盖已存在文件，第二次启动会直接崩溃。

## 已知限制

- **5555 端口重启失效**：`adb tcpip` 的端口无法持久化（需要 root 改 `persist.adb.tcp.port`），平板重启后需重新查一次端口
- **只适用于 Android**：iOS 无法作为被控端，这是系统限制
- **依赖 Tailscale**：设备列表来自 `tailscale status`；不用 Tailscale 也能手填 IP 手动连接
- **无代码签名**：首次运行会有 SmartScreen 提示
- **窗口不可为只读目录**：首次运行需要在 exe 同级目录创建 `scrcpy\`

## 常见问题

**日志里出现 `[!] 连接失败: missing`？**
端口失效了。平板重启或无线调试被关闭后，`adb tcpip` 设的 5555 会失效，重新在无线调试页看端口填进去即可。

**设备列表是空的？**
检查电脑上 `tailscale status` 能不能看到那台 Android 设备，以及两台设备是否在同一账号下、ACL 是否放行。

**scrcpy 一启动就退出？**
现在窗口会停住并显示退出码。常见原因是端口被占用、或者 scrcpy 版本与 adb 不匹配。

## License

MIT. 详见 [LICENSE](LICENSE)。
scrcpy 采用 Apache-2.0，adb 采用 Apache-2.0，均不包含在本仓库中。
