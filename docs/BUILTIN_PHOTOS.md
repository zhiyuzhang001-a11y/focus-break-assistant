# 内置实拍照片库

2026-09-06：新增 5 张横向照片，加上原有海上日出，共 6 张。下载自 Pexels 官方图像服务，保留原始比例，未生成、重绘或调色。新增文件宽度为 2560 像素。

来源页均标示 Free to use。许可核查：[Pexels License](https://www.pexels.com/license/) 允许用于 App；不得作为独立图库/壁纸平台再分发或售卖未修改的照片。此处用于休息提醒。

- **雪山静湖**：Bri Schneiter；[来源](https://www.pexels.com/photo/calm-body-of-lake-between-mountains-346529/)；`AlpineLake.jpg`；重点位置 (0.5, 0.5)。
- **山谷倒影**：Manfred Neumair；[来源](https://www.pexels.com/photo/beautiful-landscape-of-mountains-reflecting-in-a-still-lake-7204540/)；`ValleyReflection.jpg`；重点位置 (0.55, 0.58)。
- **林海远山**：Mark Stebnicki；[来源](https://www.pexels.com/photo/landscape-of-green-hills-17146221/)；`GreenHills.jpg`；重点位置 (0.5, 0.56)。
- **柔光草坡**：Mitchell Henderson；[来源](https://www.pexels.com/photo/scenic-landscape-of-green-hills-15947088/)；`RollingMeadow.jpg`；重点位置 (0.5, 0.58)。
- **开阔海岸**：Petra Nesti；[来源](https://www.pexels.com/photo/sea-landscape-beach-sand-17011301/)；`RockyCoast.jpg`；重点位置 (0.5, 0.46)。
- **海上日出**：Rıdvan Gülcan；[来源](https://www.pexels.com/photo/seascape-at-sunrise-25325735/)；`Seascape.jpg`；重点位置 (0.5, 0.52)。

资源文件与 SHA-256、下载日期、来源、裁切重点均记录在 `Sources/FocusBreakProbe/Resources/BuiltInPhotos.json`。

候选目录 `artifacts/photo-candidates-20260906/` 保留 8 张下载照片；37267779（Jansen Ruddle，树荫）、15852511（Jacob Moore，沙丘纹理）、27990819（AbduRahman Ibn Riad，沙丘）为竖幅备用，未加入内置轮换。来源分别为 https://www.pexels.com/photo/lush-green-forest-with-sunlight-filtering-through-37267779/ 、https://www.pexels.com/photo/sand-dunes-landscape-15852511/ 、https://www.pexels.com/photo/rolling-sand-dunes-with-scattered-grasses-27990819/ 。

主库偏好安静构图、自然色调和远景。亮度未做统一处理；雪山照片较暗，草坡较柔和，后续可依据体验继续筛选。
