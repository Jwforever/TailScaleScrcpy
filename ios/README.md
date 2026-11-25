# iOS 客户端定制层（overlay）

本目录存放对上游 [TheCodeboy12/scrcpy-ios-client](https://github.com/TheCodeboy12/scrcpy-ios-client) 的**增量修改**。
CI 流程：检出上游源码 → 把 `ios/overlay/` 逐文件覆盖到上游源码树 → 编译 → 打包未签名 IPA → 发布到 `scrcpy-ios` Release。

## 文件与改动

| 文件 | 改动内容 |
|---|---|
| `Sources/ScrcpyApp/ScrcpyApp.swift` | 根视图换成 `ScrcpyConnectView`；投屏时由 `MirrorSessionView` 全屏接管 |
| `Sources/ScrcpyApp/Views/ScrcpyConnectView.swift` | 全新配置页：首次使用引导 + 配对二级页、连接/断开、端口说明、分辨率与帧率选择、音频开关 |
| `Sources/ScrcpyApp/Views/MirrorSessionView.swift` | 移除整屏 `onTapGesture`（它会取消子视图触摸，导致点击失效），改为左中边缘显隐按钮 |
| `Sources/ScrcpyKit/Session/GestureController.swift` | 记录触摸起点/时长/位移；被取消时若是点击则补发 `up`；挂载时关闭上层手势的 `cancelsTouchesInView` |
| `Sources/ScrcpyKit/Session/ScrcpyClient.swift` | 新增 `ControlQueue`：控制消息单消费者队列，严格保序、MOVE 合并、长度有上限 |
| `Sources/ScrcpyKit/Video/ScrcpyVideoView.swift` | 解码输出不再逐帧跳主线程投递（`AVSampleBufferDisplayLayer.enqueue` 线程安全） |

## 已知问题与修复记录

- **点击失效**：整屏 `onTapGesture` 与触摸层冲突，`cancelsTouchesInView` 默认 true，单击被识别器认领后触摸层收到 `cancel`，安卓端判定手势取消。已通过补发 `up` + 关闭该标志修复。
- **控制间歇卡顿数秒**：原实现每条控制消息各开 `Task` 写 socket，`AdbStream.write` 只有一个 `writeContinuation` 槽会互相覆盖；DOWN/UP 无顺序保证，指针可能停在按下态。已改为串行队列。
- **字符串校验注意**：`Text("中文")` 是 `LocalizedStringKey`，不会出现在 `__cstring`；只有 `String` 类型的字面量能在二进制里 grep 到。CI 的 `VERIFY.txt` 因此选用符号名而非 UI 文案做标记。

## 产物校验

每次构建把 `BUILDINFO.txt`（commit、run 号、各源文件 sha256）和 `VERIFY.txt`（二进制标记检查）写进 `.app` 内部，下载 IPA 即可核对：
编译产物是否真的来自当前源码、补丁是否真的编进二进制。
