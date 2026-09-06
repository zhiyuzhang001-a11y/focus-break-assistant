# 阶段 0 手动场景记录

> 用途：记录必须由真实 macOS UI、锁屏/睡眠或外接硬件触发的实验。  
> 原则：一次只验证一个变量；保留原始探针输出；失败也记录，不用主观印象替代结果。

## 运行准备

```sh
swift build -c release
.build/release/focus-break-probe --watch 600
```

需要验证 Bundle 行为时：

```sh
./scripts/build-probe-app.sh
open -n .build/FocusBreakProbe.app --args --verify-bundled-overlay
```

不要为了测试自动操纵、记录或回放用户输入。idle 只观察时间值变化，不保存产生输入的内容。

`--watch` 只读取便宜的 idle 与暂停状态。只有全屏和活动屏幕场景才使用 `--watch-context`，避免常驻计时路径每秒枚举窗口边界。

## T0-01：idle 输入重置

- 日期/机器：2026-08-30 / 当前 Mac mini
- 操作：保持不输入至少 10 秒，记录 idle 增长；随后做一次普通键盘输入，再观察下一条快照。
- 预期：idle 约每秒增长；输入后在下一次 1 Hz 快照中接近 0；不出现负数或超大跳变。
- 原始输出位置：[`artifacts/stage0-idle-verification.json`](../artifacts/stage0-idle-verification.json)
- 结果：通过基础语义验证
- 结论/问题：HID any-input 与 combined any-input 一致；活动后接近 0，无活动时可增长。已发现并修复 `.null` 误用。锁屏/睡眠跨界累计另在 T0-02 至 T0-05 验证。

## T0-02：短时锁屏

- 日期/机器：2026-09-01 / 当前 Mac mini，macOS 26.5
- 操作：探针运行时锁屏约 30 秒，然后解锁。
- 预期：不得把用户会话切换事件伪装成普通锁屏；未来行为引擎应在 idle 时延后到重新活动，不在锁屏后面展示并消耗提醒。
- 原始输出位置：`artifacts/stage0-manual-lifecycle-20260901-132517`（本机忽略目录）
- 结果：失败；执行锁屏/解锁后探针事件列表为空。
- 结论/问题：`sessionDidResignActiveNotification`/`sessionDidBecomeActiveNotification`描述的是用户会话切出/切入，不足以代表普通锁屏。代码已删除伪锁屏语义；精确锁屏不作为核心正确性的硬依赖，未来通过 idle 延后与自然休息取消策略保证安全。

## T0-03：超过阈值的锁屏

- 日期/机器：待填写
- 操作：探针运行时锁屏超过 5 分钟，然后解锁。
- 预期：事件顺序稳定；未来引擎可用单调时钟确认自然休息，不补发旧提醒。
- 原始输出位置：待填写
- 结果：未执行
- 结论/问题：待填写

## T0-04：系统睡眠与唤醒

- 日期/机器：2026-09-01 / 当前 Mac mini，macOS 26.5
- 操作：探针运行时让系统进入睡眠，等待至少 30 秒后唤醒。
- 预期：睡眠前收到 `system_will_sleep`，唤醒后收到 `system_did_wake`；可能同时收到显示器事件，需记录真实顺序；唤醒后 idle/计时不补算睡眠时长。
- 原始输出位置：`artifacts/stage0-manual-lifecycle-20260901-132728`（本机忽略目录）；系统旁证为同日 `pmset -g log`
- 结果：通过；探针事件顺序为 `system_will_sleep → system_did_wake`。系统日志记录 13:28:38 进入 Software Sleep，13:28:41 唤醒。
- 结论/问题：真实系统睡眠通知可用；本次睡眠约 3 秒，只验证事件顺序，不验证超过自然休息阈值的计时语义。

## T0-05：显示器息屏与唤醒

- 日期/机器：2026-09-01 / 当前 Mac mini，macOS 26.5
- 操作：仅让显示器进入休眠，随后唤醒。
- 预期：`displaySleepState` 为 `no → yes → no`；屏幕通知可以缺失，且不误报系统整体睡眠。
- 原始输出位置：`artifacts/stage0-manual-lifecycle-20260901-132728`（本机忽略目录）；系统旁证为同日 `pmset -g log`
- 结果：首次实现失败；系统日志确认 13:27:34 `Display is turned off`，但探针未收到屏幕通知。2026-09-01 修正后复测通过，原始结果位于 `artifacts/stage0-manual-lifecycle-20260901-134353`，轮询状态序列为 `no → yes → no`，同时事件列表仍为空。
- 结论/问题：已改为用公开 `CGDisplayIsAsleep` 查询所有在线显示器并聚合三态结果；`NSWorkspace` 屏幕通知只保留为提示，不再直接决定状态。通知缺失时仍能正确检测息屏与唤醒。

## T0-06：原生全屏 Space

- 日期/机器：2026-09-01 / 当前 Mac mini，Finder 原生全屏 Space
- 操作：先在普通窗口采集快照，再进入 macOS 原生全屏 Space 采集，最后退出全屏再次采集。分别运行默认和 `--snapshot-no-accessibility` 路径。
- 预期：状态序列为 `no → yes → no`；无 AX 路径若返回 `unknown` 必须可解释，不能错误宣称 `no`。
- 原始输出位置：`artifacts/stage0-manual-fullscreen-20260901-132342`（本机忽略目录）
- 结果：通过；压缩后的真实状态序列为 `no → yes → no`。
- 结论/问题：无辅助功能授权的 WindowServer 边界路径可识别 Finder 原生全屏并在退出后恢复。

## T0-07：多显示器拓扑

- 日期/机器/显示器排列：待填写
- 操作：连接第二台显示器；让窗口和指针分别位于两台屏幕；把副屏设置在主屏左侧、右侧或上方；再断开副屏。
- 预期：数字 ID 稳定到足以完成单次会话选择；负坐标/不同缩放不影响最大交集判断；断开后回退仍有效且不崩溃。
- 原始输出位置：待填写
- 结果：未执行
- 结论/问题：待填写

## T0-08：干净权限环境

- 日期/用户账户：2026-09-01 / 当前账户 `zhiyu`；另有 `focusbreaktest`（UID 502，普通用户、非管理员）但未登录执行
- 操作：通过 LaunchServices 在当前账户启动重新签名的 Bundle；依次运行普通快照、强制无 AX 快照和 idle 信号验证，并读取运行时辅助功能授权状态。
- 预期：默认不弹权限框；基础 idle、显示器、窗口边界路径可运行；精度不足时明确返回 fallback/unknown。
- 原始输出位置：[`artifacts/current-account-test`](../artifacts/current-account-test)
- 结果：当前账户替代测试通过；普通快照与强制无 AX 快照均报告 `accessibilityTrusted=false`，活动屏幕来源均为 `frontmost_window_bounds`，正确选择唯一显示器 ID `1`，非全屏状态为 `no`；idle 的 HID any-input 与 combined any-input 一致。
- 结论/问题：已验证当前账户未授予辅助功能权限时，签名 Bundle 经 LaunchServices 启动仍可稳定走基础降级路径。该结果不等同于新账户首次运行，不能排除当前账户既有 TCC 历史的影响；按当前决策不再为本轮验证切换账户，保留这一残余风险，发布前再做真正干净环境回归。

## T0-09：辅助功能与外观

- 日期/机器：2026-09-01 / 当前 Mac mini；深色、浅色、减少动态效果、增强对比度、减少透明度
- 操作：依次切换深色/浅色、减少动态效果、增强对比度和常用界面缩放，运行浮层预览并截图。
- 预期：减少动态效果时只做极短交叉淡化；文字清晰；浮层不成为 key/main，不改变前台 PID。
- 原始输出位置：`artifacts/stage0-manual-appearance-20260901-{132411,133216,133240,133310,133329,133356}`（本机忽略目录）
- 结果：通过。深色与浅色均被正确识别；减少动态效果、增强对比度和单独减少透明度状态都被正确读取；所有运行均保持前台应用不变并点击穿透。增强对比度开启时，macOS 同时强制开启减少透明度，探针如实报告两者为 true。
- 结论/问题：四个运行时分支完成真实系统设置验证。测试后已确认恢复为深色模式，三项辅助显示设置均关闭。全屏 Space 中再次启动了浮层 Bundle，但当前界面采集工具不能可靠把另一个 App 的非激活面板合成到 Finder 截图中，因此不把该截图当作全屏可见性的通过证据。

## T0-10：长时资源与能源

- 日期/机器：2026-09-01、2026-09-04 / 当前 Mac mini；独立后台 8 小时采样已完成
- 操作：Release Bundle 正常运行 8 小时；每分钟采集 RSS 与 CPU，并以 1 Hz 保存隐私最小活动快照。正式 Instruments Energy Log 未在本批次执行。
- 预期：无持续高 Energy Impact；内存不持续增长；事件监听不会产生高频唤醒；1 Hz 轮询如成为主要能源来源则降低频率或改为事件驱动。
- 记录位置：精简验收记录为[`artifacts/stage0-resource-final-20260904.md`](../artifacts/stage0-resource-final-20260904.md)；原始批次位于 `/Users/Shared/FocusBreakAssistant-Test/stage0-resource-20260904-141156`
- 结果：完整批次取得 479 个每分钟进程样本，覆盖 28,756 秒。RSS 从 12,400 KB 降至 11,344 KB，范围 11,024–12,672 KB，线性趋势为每小时 `-70.865 KB`；平均 CPU 为 `0.012109%`。1 Hz 活动快照共 28,800 条，必需字段无缺失；启动日志为空，批次状态为 `complete`。
- 结论/问题：通过长时内存与 CPU 稳定性验收，没有持续内存增长或异常 CPU 的证据。该脚本不直接测量 macOS Energy Impact，因此正式 Energy Trace 仍是发布前残余验证；本次 8 小时内未发生系统睡眠或会话切换，这些路径继续由已有独立实测覆盖。
