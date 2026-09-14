# 记工时 App Icon 设计源文件

当前定稿为 5×5 冰蓝玻璃像素格与白色像素勾。`pixel-grid-check-master.png` 是未经重新设计的母版，保留现有构图、比例和颜色。

CI 会运行 `ios/Scripts/sync-app-icon.sh`，将母版规范化为 1024×1024，并写入 `ios/ShiftLedger/Resources/AppIcon.icon/Assets/PixelGridCheck.png`。当前只有扁平定稿，没有可靠的独立图层，因此 `.icon` 使用单个 PNG 图层并关闭额外玻璃效果，避免改变视觉。以后取得真正的分层源素材时，才应在保持外观一致的前提下升级为多层。

有效性以稳定版 Xcode 原生编译为准；`icon-composer-mcp` 只负责快速检查、预览和营销图导出。完整维护流程见 [`../../docs/app-icon-workflow.md`](../../docs/app-icon-workflow.md)。
