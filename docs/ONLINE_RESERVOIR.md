# 在线分类图库：每类 10 张

此版本取代此前的「全库 10 张 / 30 MiB、每天下载 3 张」方案。六类每类维护 10 张在线图片，正常状态合计 60 张。来源无需用户 API 密钥：

- 自然风景、动物、城市、人物：Wikimedia Commons Action API，优先 Quality images 分类，过滤绘画、示意图等元数据，保留 CC BY、CC BY-SA、CC0 或公共领域标记。
- 宇宙星空：NASA Image and Video Library 的天文观测图，剔除标记为艺术家概念图/示意图的候选，保留 NASA 及合作方署名和 NASA 媒体使用条款链接。红外、多波段合成和假色观测图仍属于天文观测，并不称为肉眼所见颜色。
- 卡通插画：Openclipart 公开搜索和图片页面，读取作者、Safe for Work 标记与公开 PNG 链接，采用网站 CC0 许可。API v2 需要注册，因此此版本没有声称使用免密钥 v2 API。

官方来源资料：

- https://www.mediawiki.org/wiki/API:Imageinfo
- https://commons.wikimedia.org/wiki/Commons:Licensing
- https://images.nasa.gov/docs/images.nasa.gov_api_docs.pdf
- https://www.nasa.gov/nasa-brand-center/images-and-media/
- https://openclipart.org/faq
- https://openclipart.org/developers

## 更新与容量

应用运行时启动检查，以后每 15 分钟检查一次。每个分类当天已有完整批次就跳过；跨天发现需要更新时准备 10 张与当前批次不同的来源图片。这里的「更新」表示从网站换一批，不能保证每张都是当天新发布的作品。睡眠、关机或退出期间不下载；再次运行后只更新当天，不补积压的历史天数。

下载到独立暂存批次，全部 10 张通过解码、尺寸和容量检查后，原子替换 active.json，再删除旧批次。不足 10 张、断网、接口限流、超容量或取消时保留旧批并清理暂存；自动失败重试至少间隔 1 小时。多进程文件锁防止命令行和应用同时改写。重启清理未完成批次，用户自存图片不进入清理范围。

专用目录：`~/Library/Application Support/FocusBreakAssistant/OnlineReservoir`，避免被系统普通缓存清理提前清空。每类最多 20 MiB，单图最多 4 MiB；常驻约 120 MiB 上限，串行更新最多额外暂存一类，峰值约 140 MiB，另有很小的清单/锁文件开销。实际文件通常远小于上限。网络会话不使用持久 URLCache，下载先在内存限量读取。

每张图的原页、下载地址、作者、许可名称和许可链接保存于对应批次的 sources.json。菜单「在线图库 · 每类 10 张」可查看当前来源、打开完整图库记录、暂停或恢复更新。「立即检查更新」仍遵守当天一次和失败重试间隔，不会反复消耗流量。

分类选择页区分「在线 10/10」与「自存」数量；自存照片可以额外添加，不受在线 10 张删除策略影响。内置风景只在没有可用在线风景或自存风景时作为后备，不重复加入已满的 10 张池子。原 Pexels 后台更新停止，新菜单不要求密钥。

## 验证与限制

缓存测试覆盖 9 张不可提交、10 张整体切换、旧批删除、崩溃暂存清理、分类隔离、容量限制和文件名检查。`--fill-reservoir` 实际填满六类；`--review-reservoir` 解码并生成检查联系表。诊断 `--fill-reservoir --replace nature` 可检查实际整批替换，正常用户更新用菜单即可。

初次素材逐张通过联系表检查。后续自动搜索仍依赖来源元数据和检索准确性，无法保证绝不出现分类不理想的图片；Openclipart 网页结构变化时更新会失败并保留旧图。用户若手动删坏专用目录或磁盘故障，不能承诺继续有完整 10 张，应用会重建或回退。真实跨日长期稳定性还需实际使用观察。
