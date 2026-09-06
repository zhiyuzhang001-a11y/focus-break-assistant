# 阶段 0：macOS 技术可行性记录

> 状态：已关闭（2026-09-06，带已记录的发布前残余验证）
> 首次验证：2026-08-30  
> 环境：Mac mini，Apple Silicon，macOS 26.5，Xcode/SDK 26.5，Swift 6.3.3

## 1. 阶段目标

在完整产品开发前验证：必要本机信号是否可得、权限成本是否合理、拒绝权限后能否降级、Horizon Gap 浮层是否不抢焦点且允许点击穿透，以及常驻探针是否有可接受的初步资源开销。

本记录只把真实运行或自动化测试覆盖的项目标记为已验证。第二台显示器、新账户首次启动和正式 Instruments Energy Trace 已明确接受为发布前残余验证，不伪装成已覆盖。

## 2. 已实现探针

```text
focus-break-probe --snapshot
focus-break-probe --snapshot-no-accessibility
focus-break-probe --watch <seconds>
focus-break-probe --watch-context <seconds>
focus-break-probe --overlay
focus-break-probe --verify-overlay
focus-break-probe --verify-lifecycle
focus-break-probe --verify-idle-signal
focus-break-probe --request-accessibility
```

输出只包含：idle 秒数、锁屏/睡眠布尔状态、显示器边界和数字 ID、活动屏幕来源、全屏三态值以及辅助功能授权状态。

明确不输出：按键、鼠标坐标、窗口标题、应用名称、URL、屏幕内容或用户文件内容。

## 3. 权限矩阵与建议降级

| 能力 | 当前 API | 系统权限 | 已验证结果 | MVP 降级策略 |
| --- | --- | --- | --- | --- |
| 系统 idle | `CGEventSource.secondsSinceLastEventType` | 未观察到额外授权 | 可读取 | 核心信号；异常值不补算时间 |
| 锁屏/解锁事件 | `NSWorkspace` session notifications | 无额外授权 | API 编译并可监听；真实锁屏待测 | 事件到达后立即暂停 |
| 系统睡眠/唤醒 | `NSWorkspace` sleep notifications | 无额外授权 | API 编译并可监听；真实睡眠待测 | 事件到达后立即暂停 |
| 显示器睡眠/唤醒 | `NSWorkspace` screen notifications | 无额外授权 | API 编译并可监听；真实息屏待测 | 事件到达后立即暂停 |
| 显示器拓扑 | `NSScreen` + `CGDisplayBounds` | 无额外授权 | 单显示器实机通过 | 找不到目标时回退主显示器 |
| 活动屏幕基础判断 | 前台 PID + `CGWindowListCopyWindowInfo` 窗口边界 | 当前机器未触发授权 | 强制关闭 AX 分支后实机通过 | 无窗口边界时回退指针所在屏幕 |
| 全屏基础判断 | 前台窗口边界与显示器边界比较 | 当前机器未触发授权 | 非全屏实机通过；真实全屏待测 | 不确定时返回 `unknown` |
| 全屏精确属性 | `AXFullScreen` | 辅助功能 | 已授权环境中非全屏实机通过 | 不是 MVP 首次启动门槛 |
| 浮层显示 | 非激活 `NSPanel` | 无额外授权 | 实机通过 | 无需系统通知权限 |

### 当前权限决定

MVP 不应默认请求辅助功能权限。基础活动屏幕选择和全屏几何判断已证明可以在禁用 AX 分支时运行。只有真实测试证明边界法的错误率不可接受，且 `AXFullScreen` 能显著改善时，才重新评估可选授权。

`--request-accessibility` 必须由开发者主动调用；探针和未来 App 不得在没有解释时自动弹出授权窗口。

## 4. 实机证据

### 4.1 默认信号快照

结果：

- 读取到一台 `2560 × 1440` 显示器；
- 活动屏幕 ID 为 `1`；
- 辅助功能已授权环境下，活动屏幕来源为 `focused_window_accessibility`；
- 当前前台窗口不是全屏；
- 坐标统一为 `quartz_global_top_left`；
- 没有读取或输出应用/窗口内容。

初版错误地把 `CGEventType.null` 当成“任意输入事件”，导致 idle 约为 73,000 秒，即使鼠标刚刚活动也不归零。Apple SDK 头文件和[官方 Event Source Token 文档](https://developer.apple.com/documentation/coregraphics/event-source-token)明确要求：查询上一次键盘、鼠标或数位板输入应使用 `kCGAnyInputEventType`。

Swift 没有直接暴露该宏，现使用其官方定义的 raw value `UInt32.max`，并选择 `.hidSystemState` 反映 HID 硬件事件。修正后的实机诊断显示：HID any-input 与 combined any-input 相差不到 1 ms；活动后 idle 可回到约 `0.006 s`；无活动时可自然增长到约 `65 s`。[最小原始证据](../artifacts/stage0-idle-verification.json)中，选定 idle 为 `1.54 s`、最近 mouseMoved 为 `1.80 s`，而错误的 null-event 仍约为 `73,200 s`。

这已足以否定 `.null` 方案并验证 any-input 基础语义。锁屏/睡眠前后的引擎累计行为仍需在真实生命周期实验中验证。

### 4.2 无辅助功能降级

运行 `--snapshot-no-accessibility` 后：

- 活动屏幕来源变为 `frontmost_window_bounds`；
- 仍正确选择显示器 ID `1`；
- 非全屏判断仍为 `no`；
- 不需要窗口标题或应用名称。

这证明基础流程在逻辑上不依赖 AX。签名 Bundle 中强制关闭 AX 分支也能运行且未触发授权请求；仍需在系统设置中真正未授权的干净用户环境复测权限身份。

### 4.3 浮层运行时行为

`--verify-overlay` 结果：

```text
frontmostApplicationUnchanged = true
ignoresMouseEvents            = true
canBecomeKey                  = false
canBecomeMain                 = false
isKeyWindow                   = false
isMainWindow                  = false
windowLevel                   = 3 (floating)
```

第一次实验使用 `.accessory` 激活策略时，虽然窗口不是 key/main，探针进程本身仍成为前台应用。改用 `.prohibited` 后前台 PID 保持不变。这个差异必须保留为正式菜单栏 App Bundle 的回归项，不能只检查 `canBecomeKey`。

进一步构建了带 `LSUIElement=true`、固定 Bundle ID 和临时签名的最小 App Bundle：

- 直接执行 Bundle 内 Mach-O 时，前台 PID 会改变；这不是正常 `.app` 启动路径；
- 通过 LaunchServices `open -n FocusBreakProbe.app` 启动时，前台 PID 显示前后均为 `9397`；
- Bundle ID 为 `com.focusbreakassistant.probe`，签名为阶段探针使用的 ad-hoc 签名；
- 由此确认正式 `.app` 启动语义下，`LSUIElement` 与非激活 `NSPanel` 的组合可保持前台应用不变。

[实机截图](../artifacts/stage0-overlay.png)证明浮层能在复杂深色桌面上渲染，位置为活动屏幕右侧偏上。截图也显示该区域可能与桌面图标重叠；这是阶段 1 的视觉环境测试项，不在阶段 0 用更强视觉效果掩盖。

### 4.4 自动化测试

`swift test`：11 个测试通过，覆盖：

- 指针所在显示器选择；
- 焦点窗口最大交集显示器选择；
- 左侧/上方显示器使用负全局坐标时的选择；
- 显示器断开后，陈旧窗口与所有屏幕零交集时返回 nil 而非任意屏幕；
- 全屏边界的 2 pt 容差；
- 浮层相对可见区域的位置计算和小屏边界约束。
- 默认可访问性视觉参数；
- 减少动态效果时的动画时长上限；
- 增强对比度时的不透明底面、强化线条和轮廓；
- 仅减少透明度时不透明但不额外增加轮廓。

### 4.5 初步性能采样

Release 构建、1 Hz 快照、运行 10 秒：

```text
real time                 10.49 s
user CPU                   0.01 s
system CPU                 0.01 s
maximum resident set      32,899,072 bytes (~31.4 MiB)
peak memory footprint      7,094,896 bytes (~6.8 MiB)
```

这只证明短时空载探针没有明显 CPU 压力。它不能替代 8 小时真实工作负载下的 Instruments Energy Log、唤醒次数和内存稳定性测试。

随后使用 macOS `System Trace` 对三种演进中的 1 Hz 路径分别采样 20 秒：

- 每秒完整读取显示器/窗口上下文：9 个 1 ms CPU 采样、280 次上下文切换、289 次系统调用；
- 只读取 idle/暂停状态、但仍初始化 `NSApplication`：2 个 1 ms CPU 采样、42 次上下文切换、79 次系统调用；
- 只读取 idle/暂停状态并改用普通 RunLoop：0 个 1 ms CPU 采样、32 次上下文切换、79 次系统调用；
- 相比最初完整路径，最终简化路径的上下文切换减少约 89%，系统调用减少约 73%；
- 简化路径的 CPU 调用栈不再出现 `CGWindowListCopyWindowInfo` 或前台应用查询。

“0 个 CPU 采样”只表示 1 ms 采样器在 20 秒内未命中目标运行片段，不代表绝对零 CPU。短样本会受 Instruments 自身和系统噪声影响，百分比只作为架构方向证据，不作为发布性能承诺。原始 `.trace` 保存在本机忽略构建目录中，不进入产品或用户数据。

尝试使用 Instruments `Power Profiler` 时，工具明确报告该模板不支持 macOS，只支持 iOS/iPadOS。因此不能用该失败 trace 宣称 Energy Impact 已验证。macOS 长时能源结论仍需 Activity Monitor 的 Energy 面板、System Trace 和 Allocations 联合观察。

### 4.6 常驻采样架构决定

- 常驻 1 Hz 路径只调用 `activitySnapshot()`：idle、会话切换、系统睡眠和显示器睡眠三态；
- 活动屏幕、前台窗口边界、显示器拓扑和全屏只在提醒到期、延后重试、显示器变化或手动预览时调用完整 `snapshot()`；
- 手动事件验证默认使用 `--watch`，只有全屏/活动屏幕实验才使用 `--watch-context`；
- 未来行为引擎不得因为实现方便而在每个计时 tick 枚举窗口。

### 4.7 生命周期与短时内存自检

`--verify-synthetic-transitions` 向工作区通知中心注入事件，只验证接线：

```text
session_switched_out → session_switched_in
system_will_sleep → system_did_wake
display_sleep_notification → display_wake_notification
```

该命令明确命名为 synthetic：会话与系统睡眠布尔值在恢复后回到 false，显示器通知只验证提示线路，不修改 `displaySleepState`。它不能证明普通锁屏、真实睡眠或息屏事件会由系统投递；旧 `--verify-lifecycle` 仅作为兼容别名保留。

最终 Release 常驻路径运行 20 秒时，RSS 在第 2、10、18 秒分别为 12,752、12,832、12,832 KB，没有观察到持续增长。受系统安全限制，`leaks` 只能读取受限内存；在这一限制下报告 `0 leaks for 0 total leaked bytes`。

作为对照，初始化完整 `NSApplication` 的旧路径约为 32,160 KB，并出现约 14 KB 的 AppIntents/LaunchServices XPC 根循环。去掉无 UI 常驻路径不需要的 `NSApplication` 后，该额外初始化消失。正式 App Bundle 仍需在长期运行中用 Allocations/Leaks 复测，因为最终菜单栏产品必须拥有应用生命周期。

### 4.8 可访问性运行时状态

浮层现监听 `accessibilityDisplayOptionsDidChangeNotification` 和有效外观变化：

- 减少动态效果：淡入/淡出最长 150 ms，已经更短的验证动画不被延长；
- 增强对比度：底面不透明、文字对比提高、Horizon 线加粗并增加 1 pt 轮廓；
- 减少透明度：底面不透明，不额外加入高对比轮廓；
- 深浅模式变化：触发重绘并重新选择对应配色。

当前机器运行时自检为深色模式，三项辅助设置均关闭；前台 PID 仍保持不变。true 分支已由纯策略测试覆盖，但仍需实际切换系统设置做视觉确认。

### 4.9 非侵入式全屏候选扫描

在不切换 Space、不激活其他应用且不读取名称、PID、标题或内容的前提下，扫描 WindowServer 的窗口边界：

```text
displayCount             = 1
layerZeroWindowCount     = 13
fullFrameCandidateCount  = 0
```

当前系统没有与显示器边界匹配的真实全屏候选，因此无法在不改变用户桌面的情况下取得 `focusedWindowFullScreen = yes` 证据。现有几何测试只能证明边界算法，不能替代原生全屏 Space 实测。

### 4.10 当前账户未授权 Bundle 验证

2026-09-01 重新构建并通过 LaunchServices 在当前 `zhiyu` 账户运行签名 Bundle。普通快照与强制无 AX 快照都报告 `accessibilityTrusted=false`，并得到一致结果：

- 活动屏幕来源为 `frontmost_window_bounds`；
- 正确选择唯一显示器 ID `1`；
- 当前非全屏状态为 `no`；
- idle 信号中 HID any-input 与 combined any-input 一致；
- 三个命令均生成有效 JSON，未崩溃。

原始结果保存在 [`artifacts/current-account-test`](../artifacts/current-account-test)。这证明当前账户未授权状态下的 App Bundle 降级路径可运行，但不等同于新建账户的首次启动测试；本轮接受 TCC 历史状态这一残余风险，真正干净环境验证移至发布前回归。

### 4.11 阶段 0 收尾工具链

新增安全自动回归、人工场景采集和长时资源采样脚本。安全回归已实跑通过，覆盖 13 个单元测试、Release Bundle 签名、LaunchServices 普通/无 AX 快照、idle 一致性和合成通知接线。长时采样脚本的 12 秒链路自检取得 6 个稳定进程样本，RSS 为 12,496–12,720 KB，平均 CPU 0.0333%。这些数字只验证采样链路，不替代 8 小时结论。

具体执行顺序和风险接受规则见[阶段 0 收尾执行计划](STAGE_0_EXECUTION_PLAN.md)。

### 4.12 全屏与真实生命周期实测

2026-09-01 完成首轮真实系统场景：

- Finder 原生全屏的无 AX 状态序列为 `no → yes → no`，通过；
- `pmset sleepnow` 触发真实系统睡眠，探针收到 `system_will_sleep → system_did_wake`，系统电源日志也记录进入 Software Sleep 和随后唤醒，通过；
- 普通锁屏/解锁后事件列表为空。Apple 文档把 session active/resign 定义为用户会话切入/切出，因此现有实现不能把它当作普通锁屏信号；
- 系统电源日志确认显示器已关闭，但首版探针没有收到 screens sleep/wake 事件；该问题随后在 4.13 通过状态查询修正；
- 深色、浅色、减少动态效果、增强对比度和单独减少透明度均完成真实设置切换，Bundle 浮层始终保持前台应用不变并点击穿透；测试后恢复原设置。

这些实测推翻了“注入同名通知通过即可代表真实锁屏/息屏”的假设。显示器息屏已在 4.13 修正；普通锁屏不再伪造确定性信号，仍需由未来行为引擎的 idle 延后策略保证提醒安全。

### 4.13 生命周期信号修正与息屏复测

现已删除错误的“session 通知等于普通锁屏”语义：输出改为 `sessionInactive`，事件改为 `session_switched_out/in`。普通锁屏不再伪造确定性布尔值。

显示器状态改为公开 `CGDisplayIsAsleep` 的逐显示器查询：所有在线显示器均睡眠时为 `yes`，任意显示器醒着时为 `no`，查询失败或列表为空时为 `unknown`。`NSWorkspace` 屏幕通知只输出提示事件，不直接修改状态。

真实 `pmset displaysleepnow` 复测中，系统依旧没有投递屏幕通知，但新探针稳定得到 `displaySleepState: no → yes → no`，证明修正路径不依赖缺失通知。新增聚合策略测试后，`swift test` 为 13 个测试通过；20 秒新常驻路径采样 RSS 为 12,720–12,832 KB，平均 CPU 0.07%。

## 5. 已发现并修正的问题

1. SwiftPM 命令行可执行文件不会自动创建 `NSApplication`；首次浮层运行因此在 `NSApp` 处崩溃。已改为显式使用 `NSApplication.shared`。
2. “窗口不能成为 key/main”不足以证明“不抢焦点”；`.accessory` 探针启动仍改变前台 PID。已增加前台 PID 运行时自检，并在探针中使用 `.prohibited`。
3. AppKit/AX 与 WindowServer 的坐标原点不同。信号层现统一使用 Quartz 全局左上角坐标，浮层展示层继续使用 AppKit 可见区域坐标。
4. 基础活动屏幕判断原本依赖辅助功能。已加入 WindowServer 边界路径，并用强制禁用 AX 分支验证。
5. 最初的 1 Hz 探针每秒读取完整窗口上下文。System Trace 显示主要运行样本落在 WindowServer/LaunchServices；现已拆成便宜的常驻活动快照和按需展示上下文。
6. 无 UI 的 `--watch` 原本为了 Timer 初始化整个 `NSApplication`，带来约 19 MB RSS 与额外 XPC 根循环。已改为普通 RunLoop；只有浮层/App Bundle 路径创建 `NSApplication`。
7. 初版 idle 使用 `.null`，在当前系统上返回约 20 小时而不是上一次输入时间。已按 Apple 官方定义改为 HID 状态的 `kCGAnyInputEventType`，并增加 `--verify-idle-signal` 防止再次混淆。

## 6. 尚未完成的阶段 0 验证

- [x] 真实宿主输入后 any-input idle 及时归零并可平稳增长；
- [x] 普通锁屏信号边界已明确：session 通知方案实测失败并已删除伪锁屏语义；未来行为引擎使用 idle 延后保证安全；
- [x] 系统睡眠/唤醒真实事件顺序；
- [x] 显示器息屏/唤醒状态序列；公开状态查询实测为 `no → yes → no`；
- [ ] 第二台显示器连接、断开、负坐标排列和活动屏幕切换；
- [x] 原生全屏 Space 中识别为 `yes`，退出后恢复为 `no`；
- [x] 当前账户中辅助功能未授权时不崩溃且降级路径稳定；真正干净账户首次启动移至发布前回归；
- [x] `LSUIElement` App 通过 LaunchServices 启动并显示浮层时，前台应用保持不变；
- [x] 减少动态效果、增强对比度、减少透明度和深浅模式运行时切换；
- [x] 独立 8 小时 RSS/CPU 稳定性采样；正式 Instruments Energy Trace 保留到发布前。

## 7. 阶段退出判断

阶段 0 于 2026-09-06 关闭。信号获取、低权限降级、系统睡眠、显示器息屏、真实全屏、外观适配和临时浮层已有直接证据；独立 8 小时资源采样完整结束且未发现持续内存增长或异常 CPU。多显示器、新账户首次启动和正式 Instruments Energy Trace 已明确延期，不再伪装成已验证。

本机只有一台显示器，因此多显示器实测等待硬件。普通锁屏没有可靠的公开精确信号，已通过删除错误映射并规定未来 idle 延后策略接受该边界。上述残余项不阻塞 Stage 1，但在发布前必须重新进入验收清单。

干净权限账户的前置条件已完成：本机已创建普通用户 `focusbreaktest`（UID 502，非 admin），且 `/Users/Shared/FocusBreakAssistant-Test` 中的签名 App、运行脚本和结果目录权限已核验。根据当前决策，本阶段用 `zhiyu` 账户中已确认的 `accessibilityTrusted=false` 状态完成降级验证，不再切换账户；新账户首次启动保留为发布前回归项。

后续顺序：

1. 按 Stage 1 收尾计划完成候选收敛、正式资产和体验验收；
2. 有第二台显示器时补做拓扑实验；
3. 发布前补做正式 Energy Trace，并在新账户复测首次启动 TCC 行为；
4. 阶段 2 行为引擎实现 idle 延后与自然休息取消，不依赖精确普通锁屏信号。
