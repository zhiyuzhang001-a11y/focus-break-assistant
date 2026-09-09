# Stage 1 网络素材候选记录

> 2026-09-06 最新要求：禁止自行生成图片。正式资源现已改用现成莫奈作品；下文生成资源部分仅为历史记录。当前来源与展示规格见 [ARTWORK_SOURCE.md](ARTWORK_SOURCE.md)。

> 建立日期：2026-09-04  
> 状态：候选收敛已完成；用户于 2026-09-06 选择“半透明日光”，正式深浅资源已进入 App。

## 硬性规则

- 只从作者/素材站官方页面下载原始文件，不使用搜索结果缩略图；
- 下载后的文件必须逐像素确认无水印、无文字、无 Logo；
- 页面必须明确标示可下载、可修改及商业/App 使用许可；
- 保存作者、原始页面、下载日期和许可证记录；
- 来源或许可有疑问时直接淘汰，不做去水印处理。

## 第一轮来源候选

### 抽象光与空间

- [Soft pastel gradient with subtle color shifts](https://unsplash.com/photos/soft-pastel-gradient-with-subtle-color-shifts-wyfGdPxSt-c) — Omar Lopez-Rincon，页面标示 Free / Unsplash License。低细节柔和渐变，需检查是否过于像通用系统壁纸。
- [Abstract blue and golden gradient](https://unsplash.com/photos/abstract-blue-and-golden-gradient-MQAhiwd6xJM) — Liana S，页面标示 Free / Unsplash License。冷暖交界可以表达停顿，需压低中央亮部避免刺激。
- [Abstract Light and Shadow Minimalist Art](https://www.pexels.com/photo/abstract-light-and-shadow-minimalist-art-34864774/) — Francesco Paggiaro，页面标示 Free to use / Pexels License。适合验证非具象方向，需确认裁切后不产生强烈视觉中心。

### 材质与留白

- [Sheer curtains with sunlight casting shadows](https://unsplash.com/photos/sheer-curtains-with-sunlight-casting-shadows-s1fDNMC-1T8) — Christopher Stites，页面标示 Free / Unsplash License。轻质、透气，但需降低线条对比度和室内叙事感。
- [Sunlight shines through sheer curtains with leaf shadows](https://unsplash.com/photos/sunlight-shines-through-sheer-curtains-with-leaf-shadows-wi-78W-29D8) — Guy Grandjean，页面标示 Free / Unsplash License。自然但不依赖远景，需检查叶影是否过密。
- [Sunlight streams through a sheer curtain](https://unsplash.com/photos/sunlight-streams-through-a-sheer-curtain-in-a-room-eM1xMVLVjKA) — Gunther Samson，页面标示 Free / Unsplash License。可表达片刻停顿，需避免被读成室内摄影展示。

### 时间与停顿

- [Water Ripple](https://www.pexels.com/photo/water-ripple-2584060/) — K，页面标示 Free to use / Pexels License。单一涟漪有停顿语义，但要避免冥想 App 套路感。
- [Abstract Ripples in Tranquil Water Surface](https://www.pexels.com/photo/abstract-ripples-in-tranquil-water-surface-32685815/) — Sucipta Mahendra，页面标示 Free to use / Pexels License。非叙事纹理，需检查重复纹理密度。
- [Serene Abstract Water Ripples in Golden Light](https://www.pexels.com/photo/serene-abstract-water-ripples-in-golden-light-28602566/) — Karolina，页面标示 Free to use / Pexels License。冷暖时间感较强，需检查金色高光是否过亮。

## 下一道筛选

以上页面只通过“来源可追溯、页面许可清晰”的发现检查。下一步必须下载官方原始文件后检查水印、分辨率和元数据，再统一制作低干扰桌面合成图。任何候选都不能因为题材符合描述而跳过实机场景测试。

## 用户补充的时间与生命隐喻

用户补充：钟表、沙漏、流水、地球自转/公转、落花、落叶、日出和动物出生。这些内容不绑定某种画风，按是否帮助用户离屏休息来筛选。

已发现的官方来源种子：

- [Clock at 8:00](https://www.pexels.com/photo/clock-at-8-00-2227122/) — Pexels / Free to use；可测试时间器物，但需避免倒计时与时间管理暗示。
- [Hourglass](https://www.pexels.com/photo/hourglass-8573370/) — Pexels / Free to use；哲学含义直接，但产品化风险是像截止提醒。
- [Abstract Long Exposure of Flowing Water](https://www.pexels.com/photo/abstract-long-exposure-of-flowing-water-36744020/) — Pexels / Free to use；适合表达流动，需避免高频水纹。
- [Fallen Leaf on Water](https://www.pexels.com/photo/fallen-leaf-on-water-18942271/) — Pexels / Free to use；适合表达季节和放下，需避免悲伤或“禅意模板”感。
- [Seascape at Sunrise](https://www.pexels.com/photo/seascape-at-sunrise-25325735/) — Pexels / Free to use；适合表达新周期，需压低日出高光。
- [The Blue Marble](https://visibleearth.nasa.gov/images/57723/the-blue-marble) — NASA Visible Earth；画面来源清晰，但进入商业产品前必须继续按 NASA Media Usage Guidelines 核查署名、Logo、第三方权利与不得暗示背书的要求。

动物出生暂不下载。它的情感和叙事强度很可能让用户继续看屏幕，并且比无人物自然素材更容易出现伦理、版权与接受度问题；只有其他隐喻验证失败时再进入对照。

## 已完成的首轮原图核验与合成

已从 Pexels 官方页面取得三个代表性原图预览，均未观察到水印、文字、Logo 或人物：

- `sources/abstract-light-shadow.png`
- `sources/sheer-curtain.png`
- `sources/water-ripple.png`

已生成两轮真实工作界面概念合成，第二轮收敛了亮度、提醒高度和视觉中心：

- `mockups/01-abstract-light-space-v2.png`
- `mockups/02-translucent-material-v2.png`
- `mockups/03-time-and-pause-v2.png`

根据用户补充的时间与生命隐喻，又完成四张对照：

- `mockups/04-time-instrument-clock.png`
- `mockups/05-flowing-water.png`
- `mockups/06-fallen-leaf.png`
- `mockups/07-sunrise-cycle.png`

这些是体验比较稿，不是最终产品资产；其中的桌面、代码和文字均不能直接进入 App。最终实现仍须使用原始授权素材和原生 Swift 文案。

## 最终选择与正式资源

- 用户在水波停顿、半透明日光、缓慢流水三个终选中选择半透明日光；理由是水波偏白、流水偏黑，半透明日光亮度更均衡。
- 正式资源由内置图像生成工具根据 `02-translucent-material-v2.png` 的材质与光线方向重新生成，不直接打包概念稿或原始照片；所有文字、桌面、窗口、图标和菜单栏均被排除。
- 浅色提示要求暖亚麻、低对比度、无纯白高光；暗色提示经一次定向修正，提升为暖灰棕中间调，避免接近黑色。
- 资源保存为 `Sources/FocusBreakProbe/Resources/AtmosphereLight.png` 和 `AtmosphereDark.png`，均为 `1040 × 256 px` RGB PNG；中文文案继续由 AppKit 原生绘制。
- 资源 SHA-256：浅色 `372a69d7d9b7a6c66aeb326069c376cc9229147f12ee4511a9808c5f16e3d515`；暗色 `899f923a6266a664b51301243864f86c12ab9fc4f846aee7fa48567c095153c1`。
- 参考页在 2026-09-06 仍标示 `Free to use`；Pexels License 同日仍明确允许免费使用、修改并用于 App。正式资源是生成后的新资产，但仍保留参考来源链以便审计。
