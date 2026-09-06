# Focus Break Assistant

隐私优先、低打扰的 macOS 离屏休息助手。“阶段 0：技术可行性探针”已关闭，当前正在完成“阶段 1：视觉提醒原型”，尚不是可发布产品。

## 当前内容

- `FocusBreakProbeCore`：与 AppKit 无关的显示器选择、全屏几何判断和浮层位置策略；
- `focus-break-probe`：idle、会话切换、系统睡眠、显示器睡眠三态、活动屏幕、全屏和权限探针；常驻活动快照与按需窗口上下文分离；
- Horizon Gap “半透明日光”浮层：内置深浅氛围资源、原生中文、无声音、不可成为 key/main window、点击穿透；
- 自动化测试与本机阶段 0 实验记录。

探针不会读取或输出按键、鼠标位置、窗口标题、应用名称或屏幕内容。

idle 使用 Core Graphics 的 HID `kCGAnyInputEventType` 语义，只读取距离上一次输入的秒数；不安装键盘事件监听，也不记录具体输入事件。

## 运行

需要 macOS 14 或更高版本及 Xcode Command Line Tools。

```sh
swift test
swift run focus-break-probe --snapshot
swift run focus-break-probe --snapshot-no-accessibility
swift run focus-break-probe --watch 30
swift run focus-break-probe --watch-context 30
swift run focus-break-probe --overlay
swift run focus-break-probe --preview-menu
swift run focus-break-probe --verify-overlay
swift run focus-break-probe --verify-synthetic-transitions
swift run focus-break-probe --verify-idle-signal
./scripts/build-probe-app.sh
.build/FocusBreakProbe.app/Contents/MacOS/focus-break-probe --verify-bundled-overlay
./scripts/prepare-clean-account-test.sh
./scripts/run-stage0-safe-tests.sh
./scripts/run-stage0-manual-test.sh fullscreen 90
./scripts/run-long-resource-test.sh 28800 60
./scripts/start-long-resource-test-detached.sh 28800 60
./scripts/run-stage1-visual-tests.sh
./scripts/run-preview-menu.sh
```

`--request-accessibility` 只用于显式权限实验，不是默认运行路径。基础降级路径无需该权限即可从 WindowServer 窗口边界和指针位置选择活动屏幕；无法可靠判断全屏时返回 `unknown`，不伪造确定性。

普通锁屏没有可靠的公开事件，因此探针不把用户会话切换伪装成锁屏。显示器睡眠以公开 `CGDisplayIsAsleep` 状态查询为真值；系统屏幕通知只作为可选提示。

## 项目依据

- [长期计划](LONG_TERM_PLAN.md)
- [下一步执行计划](docs/NEXT_EXECUTION_PLAN.md)
- [阶段 1 视觉原型记录](docs/STAGE_1_VISUAL_PROTOTYPE.md)
- [Stage 1 艺术方向重构](docs/STAGE_1_ART_DIRECTION.md)
- [Stage 1 试用反馈模板](docs/STAGE_1_FEEDBACK_TEMPLATE.md)
- [阶段 0 技术可行性记录](docs/STAGE_0_FEASIBILITY.md)
- [阶段 0 收尾执行计划](docs/STAGE_0_EXECUTION_PLAN.md)
- [浮层实机截图](artifacts/stage0-overlay.png)
