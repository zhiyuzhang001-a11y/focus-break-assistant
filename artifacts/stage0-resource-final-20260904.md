# Stage 0 独立 8 小时资源验收

> 批次：`stage0-resource-20260904-141156`
> 验收日期：2026-09-06
> 原始位置：`/Users/Shared/FocusBreakAssistant-Test/stage0-resource-20260904-141156`

## 结果

- 批次状态：`complete`
- 目标时长：28,800 秒
- 进程采样：479 个，每次间隔均在 55–65 秒内，时间戳单调递增
- 覆盖时长：28,756 秒
- RSS：首个 12,400 KB，末个 11,344 KB，范围 11,024–12,672 KB
- RSS 线性趋势：每小时 `-70.865 KB`
- 平均 CPU：`0.012109%`
- 活动快照：28,800 条，必需字段缺失数为 0
- 显示器状态：`no` 13,679 条，`yes` 15,121 条
- 系统睡眠与会话切换：本批次中均未发生；由 Stage 0 的独立实机场景覆盖
- `launcher.err` 与 `launcher.log`：空
- 批次结束后 LaunchAgent 已卸载

## 完整性校验

```text
activity.ndjson      ec65da6abb2758930b1bdb6d020edb1a2e337d21e530c9ae29173c8d1a439111
process-samples.csv  4c57a5cdb203be7291f58809b8ee5e941a8ae11eca4175c53545dde7734b4356
run-status.txt       ac0dac0d6da0e849bc32a0a3fae549f0a169694a41d9cfdc4c3d608283fb215d
summary.txt          b518217f9afcf3c5cf21fd83cb92aab3bff743fe5de75d4f38c5f429c478e773
```

原始 1 Hz 流水约 4.5 MB，属于可重复生成的本机诊断产物，不提交到 Git；本文件保留关键指标、边界和原始文件 SHA-256，避免项目被大量运行产物拖慢。

## 决定

本批次没有持续内存增长、异常 CPU、异常退出或错误日志的证据，满足 Stage 0 的长时稳定性退出条件。接受以下残余风险并关闭 Stage 0：

- 尚未执行正式 Instruments Energy Trace；发布前补做。
- 本批次没有覆盖系统睡眠或会话切换；已有独立实测覆盖事件与状态语义。
- 多显示器与新账户首次启动等待硬件或发布前环境。
