# 记工时 App Icon 设计源文件

当前定稿为“海湾渐变”日历：收窄的蓝色顶栏、两枚等径中空装订孔、4 × 3 日期点与一个蓝色高亮点。所有源素材均为 1024 × 1024 平面 SVG，不预制阴影、高光或玻璃效果。

- `calendar-background.svg`：白色圆角日历底板。
- `calendar-header.svg`：`#0879F9 → #2F9BFF` 海湾渐变顶栏；两枚装订孔使用偶奇填充形成真实透明镂空。
- `date-dots.svg`：11 枚独立淡灰圆点，每枚圆点保留独立 SVG `id`。
- `active-day.svg`：当前日期高亮圆点，使用同一海湾渐变。
- 装订孔与日期点半径均为 40，视觉尺寸完全一致。

CI 会运行 `ios/Scripts/sync-app-icon.sh`，把四个 SVG 同步到 `AppIcon.icon/Assets/`。材质、深色适配与系统着色由 Apple Icon Composer / Xcode 在编译阶段渲染，SVG 内不烘焙玻璃效果。

有效性以稳定版 Xcode 原生编译为准；`icon-composer-mcp` 只负责快速检查、预览和营销图导出。完整维护流程见 [`../../docs/app-icon-workflow.md`](../../docs/app-icon-workflow.md)。
