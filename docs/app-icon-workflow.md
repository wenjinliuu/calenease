# App Icon 维护工作流

## 文件位置

- 设计母版：`DesignAssets/AppIcon/*.svg`（四个独立矢量图层）
- Xcode 编译文件：`ios/CalenEase/Resources/AppIcon.icon/`
- 素材同步脚本：`ios/Scripts/sync-app-icon.sh`
- 工程设置：`ios/project.yml`，App Icon 名称为 `AppIcon`

`Assets.xcassets` 继续保存 AccentColor、启动背景等普通资源。旧的 `AppIcon.appiconset` 已移除，避免和同名 `.icon` 冲突。

## 修改方式

修改四个 SVG 设计母版并 push 即可。三个 iOS workflow 都会先把它们同步成 1024 × 1024 的 `.icon` 矢量图层，再交给 Xcode。不要在 Asset Catalog 里重新创建另一个 `AppIcon`。

当前 `.icon` 使用 Apple 正式支持的分层 SVG 结构：背景、顶栏、日期点、高亮点各自独立。SVG 只保存平面形状与基础颜色，不包含位图、不烘焙玻璃、高光或阴影；这些材质统一由 Icon Composer 配置与 Xcode 渲染。顶栏的装订孔是 SVG 偶奇填充形成的透明镂空，不使用白色位图覆盖。

## CI 的判断顺序

1. `App Icon Preview / Xcode native icon validation` 使用最新稳定版 Xcode 生成工程并执行 unsigned Release archive；只有归档内成功生成 `Assets.car` 与 `AppIcon*.png` 才算有效。
2. `iOS Build & Test` 再次原生编译图标并运行全部单元测试。
3. `TestFlight` 在归档后检查归档内的图标产物，再沿用原有签名与上传流程。
4. `App Icon Preview / Third-party preview` 使用固定版 `icon-composer-mcp` 做 inspect、六种外观预览与营销 PNG 导出。它是非阻塞辅助工具，兼容问题不会否定已通过的 Xcode 构建。

生产工作流只使用 `latest-stable`，不依赖 Xcode Beta 或 Icon Composer Beta。未来若引入 Icon Composer 新格式或真正分层素材，应先让 Xcode 原生验证通过，再考虑更新第三方预览器。
