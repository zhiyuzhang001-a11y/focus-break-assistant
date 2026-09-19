# 当前照片与展开效果

## 应用图标

- 文件：`Support/FocusBreakAssistant-icon-source.png` 与由其按 macOS 图标规范缩放导出的 `Support/FocusBreakAssistant.icns`。
- 来源：用户于 2026-09-19 在本项目对话中提供。
- 许可：用户提供素材，许可状态未核实；仅作为本项目应用图标使用。未使用 AI 生成、重绘或生成式编辑。

- 照片：Seascape at Sunrise，Rıdvan Gülcan / Pexels。
- 来源：https://www.pexels.com/photo/seascape-at-sunrise-25325735/
- 下载：https://images.pexels.com/photos/25325735/pexels-photo-25325735.jpeg?auto=compress&cs=tinysrgb&w=2400
- 下载日期：2026-09-06；2400 × 3600；文件：Sources/FocusBreakProbe/Resources/Seascape.jpg。
- 许可：Pexels License，来源记录见此前网络素材候选记录。使用现成摄影原图，未生成或重绘。

画面水平居中、顶部贴近屏幕可用区域上沿，宽 90%、高 65%，占可用面积 58.5%。照片位置与比例固定，遮罩下边缘在 2.8 秒内向下移动，像窗帘一样展开。28–48 pt 自适应白色半粗体文字位于照片中央，无背景框。减少动态效果开启时使用短淡入。

用 `--verify-curtain` 可采样真实 Core Animation presentation 遮罩，检查顶部固定、显示高度逐步增加且最终完全展开。此前绘画和整体下滑方案均已替换。


照片重点配置位于 `Sources/FocusBreakProbe/Resources/Photo.json`：`resourceName` 指定照片，`focalX` / `focalY` 为从左上角计的 0–1 坐标。当前海景重点为 (0.5, 0.52)。替换人物照时应把重点设在人脸附近；这是逐张配置，不是自动人脸识别。裁切保留重点位置，不承诺在所有屏幕比例下保留整个人物或全部风景。

布局使用目标屏幕的可用区域与逻辑点，每次展示重新计算，避免菜单栏和 Dock；Retina 像素倍率不参与字号计算。验证覆盖小屏、竖屏、超宽屏、大屏以及负坐标副屏，渲染矩阵共 18 张。
