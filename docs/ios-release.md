# 省心日历 iOS 上架指南

iOS 版是 SwiftUI 原生实现（`ios/`），和网页版共用同一套业务规则与备份格式。
本文只讲发布，工程结构见 [`../ios/README.md`](../ios/README.md)。

## 一、现状速览

以下 App Store Connect / Apple Developer 的值由 `TestFlight` 工作流的核对步骤
（中央仓库 `ios-ci-workflows` 的 `scripts/asc-verify.py`，App Store Connect API 只读查询）实际读出，2026-09-24 核对。

| 项目 | 值 |
| --- | --- |
| App Store Connect App 名称 | 省心日历-循环班表（Apple ID 6815659759，主要语言 zh-Hans） |
| SKU | `calenease-ios` |
| Bundle ID | `com.wenjinliu.calenease`（Identifiers 里的名称 CalenEase，已开 iCloud 能力） |
| App 名称（桌面显示） | 省心日历 |
| Xcode 工程 / Scheme | `ios/CalenEase.xcodeproj` / `CalenEase` |
| iCloud 容器 | `iCloud.com.wenjinliu.calenease`（需在 App ID 上勾选，见下文） |
| 版本 / Build | `MARKETING_VERSION = 1.0.0`，`CURRENT_PROJECT_VERSION = 1` |
| 设备 | 仅 iPhone（`TARGETED_DEVICE_FAMILY = 1`），仅竖屏 |
| 最低系统 | iOS 26 |
| 隐私清单 | `ios/CalenEase/Resources/PrivacyInfo.xcprivacy`（无收集、无跟踪） |
| 隐私政策页 | `/privacy/`，线上地址 https://wenjinliuu.github.io/calenease/privacy/ |
| 技术支持页 | https://wenjinliuu.github.io/calenease/support/ |

旧版「循环班表」（`com.wenjinliu.shiftledger`，SKU `shift-ledger`）是另一个 App，
新 App 读不到它沙盒里的数据；老用户在旧版导出备份（或直接用旧版 iCloud 云盘
「循环班表」文件夹里的备份），在新 App「设置 › 备份 › 从文件导入」即可恢复，格式完全兼容。

版本号、Bundle ID、Info.plist 全部由 `ios/project.yml` 生成，改完重新
`./Scripts/bootstrap.sh` 即可，不要手工改 `.xcodeproj`（它不入库）。

## 二、本地环境要求

- macOS + Xcode 26 及以上（iOS 26 SDK）
- `brew install xcodegen`
- Apple Developer Program 会员（个人 99 美元/年）——账号审核通过后才能真机调试与上架

## 三、构建流程

```bash
cd ios
./Scripts/bootstrap.sh --open   # 生成 CalenEase.xcodeproj 并打开
```

Xcode 里一次性配置：

1. 选中 `CalenEase` target → **Signing & Capabilities**
   - 勾选 Automatically manage signing
   - Team 选自己的开发者账号（审核通过后才会出现）
   - 确认 Bundle Identifier 为 `com.wenjinliu.calenease`
2. 真机跑一遍，重点验证：
   - 循环排班生成整年班表，往后翻月份能自动延续
   - 单日改班后，重新进入不会被循环覆盖
   - 设置页导出备份能拉起分享面板；导入网页版导出的 JSON 能还原
   - 杀进程重开数据仍在（写在 Application Support 的 `calenease.json`）

## 四、提交到 App Store Connect

1. **App 已创建**：「省心日历-循环班表」，Bundle ID `com.wenjinliu.calenease`，SKU `calenease-ios`，
   主要语言简体中文。想核对就跑一次 `TestFlight` 工作流并勾选「只核对」，日志里会列出全部 App、
   Bundle ID、SKU 和各 App ID 的 iCloud 容器。
2. **归档上传**：两条路都行
   - CI（推荐）：仓库 Actions → `TestFlight` → Run workflow，或推一个 `v*` tag。
     第一步先用 API 核对 Bundle ID 与 App 都已注册，缺了直接报错，不再等到签名才失败。
     归档阶段不签名，发布签名由导出阶段的 App Store Connect 密钥自动签发——
     带自动签名归档会去申请「开发」描述文件，而它要求团队里注册过设备，CI 上必然失败。
   - 本地：Xcode → Product → Destination 选 `Any iOS Device` → Archive → Distribute App
3. **填写元数据**（草稿见下节），上传截图：
   - 至少提供 6.9 英寸 iPhone 截图（1320×2868）3–10 张，其余尺寸 Apple 会自动缩放
   - 在 6.9 英寸模拟器（如 iPhone 17 Pro Max）上截取；也可以手动运行 `Build & Test / Agent Preview`，
     把 `simulator_name` 设为 `iPhone 17 Pro Max`，从产物的 `launch.png` 或实时预览里截图
4. **App 隐私**：选择「不收集数据」；隐私政策 URL 填上面那个线上地址
5. **App 审核信息**：无需登录账号，备注里写明「离线本地工具，无账号体系，无服务器」
6. 先用 TestFlight 自测一轮，再提交审核

### TestFlight 工作流需要的 Secrets

在仓库 `Settings → Secrets and variables → Actions` 添加：

| Secret | 说明 |
| --- | --- |
| `APPLE_TEAM_ID` | 10 位 Team ID（开发者账号 Membership 页面） |
| `APP_STORE_CONNECT_KEY_ID` | App Store Connect API 密钥 ID |
| `APP_STORE_CONNECT_ISSUER_ID` | 同页面的 Issuer ID |
| `APP_STORE_CONNECT_PRIVATE_KEY` | `.p8` 私钥文件的完整内容（含 BEGIN/END 行） |

API 密钥在 App Store Connect → 用户和访问 → 集成 → App Store Connect API 创建，
角色至少选 **App Manager**（要让 `xcodebuild -allowProvisioningUpdates` 能自动创建证书和描述文件）。
只能下载一次，注意保存。构建号默认取 GitHub run number。

### iCloud 备份

App 把备份写进 iCloud 云盘容器 `iCloud.com.wenjinliu.calenease`（「文件」App 里显示为「省心日历」文件夹）。
需要在 Apple Developer → Identifiers → `com.wenjinliu.calenease` → iCloud → 勾选 CloudKit/iCloud Documents，
并建好、勾选这个容器。TestFlight 工作流从该 App ID 的描述文件里读出实际勾选的容器：

- 容器在 → 给包加上 iCloud 权限；
- 容器不在，或还没有描述文件可查（新 App 第一次导出之前）→ 这次不加 iCloud 权限并在日志里警告，
  App 里的备份自动存到本机并提示原因。第一次上传成功后描述文件就有了，下一次构建会自动核对并启用。

容器名定在 `CalenEase.entitlements`、`ICloudBackupStore.containerID`、`project.yml` 的 `NSUbiquitousContainers`
和 `testflight.yml` 的 `ICLOUD_CONTAINER` 四处，要改一起改。

## 五、元数据草稿（可直接改用）

- **副标题**：为倒班人群设计的排班与工时账本
- **关键词**：倒班,轮班,排班,班表,工时,加班,四班三倒,考勤,值班,夜班
- **描述**：
  > 省心日历（原名循环班表）是为不按星期工作的人设计的个人排班日历。自定义班次、职责标签与循环模板，
  > 按四班两倒、做二休二、三班倒等常见规律自动生成整年班表；工时与加班分别统计，
  > 支持标准工时、综合计算工时、不定时工时与手动记录；自动识别法定节假日并推算每月
  > 基本工时。全部数据保存在设备本机，不需要注册登录，支持 JSON 备份导出与恢复。
- **年龄分级**：4+
- **类别**：主要「效率」，次要「商务」

## 六、审核常见风险与应对

| 风险 | 说明 | 应对 |
| --- | --- | --- |
| 2.1 完整性 | 空白首屏被判为无功能 | 首次进入是空日历，审核备注里说明「点右上角『循环排班』可一键生成整年班表」 |
| 4.2 最低功能 | 工具类应用功能过薄 | 本工程是原生实现，含循环推算、工时与加班统计、法定节假日与基本工时推算、备份恢复，并非网页镜像 |
| 5.1.1 隐私 | 缺隐私政策链接 | 已提供 `/privacy/` 页面，App 内「设置 → 关于」也有入口 |
| 导出合规 | 每次上传都被问加密 | `project.yml` 已设 `ITSAppUsesNonExemptEncryption: false` |
| 隐私清单 | 使用 UserDefaults / 文件时间戳 API | 已提供 `PrivacyInfo.xcprivacy` 并声明理由（CA92.1 / C617.1） |

## 七、后续发版流程

1. 改代码 → `cd ios && xcodegen generate` → Xcode 里跑单测（或等 CI 的 `iOS Build & Test`）
2. 改 `ios/project.yml` 里的 `MARKETING_VERSION` 或 `CURRENT_PROJECT_VERSION`
3. 手动触发 `TestFlight` 工作流，或本地 Archive → Upload
4. App Store Connect 提交新版本

网页版仍由 `main` 分支的 GitHub Pages 工作流自动发布，两端共用同一套规则与备份格式。
