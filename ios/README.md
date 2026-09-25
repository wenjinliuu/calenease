# 省心日历 iOS（CalenEase）

省心日历（原名循环班表）的 iOS 原生版：SwiftUI + Liquid Glass，完全离线的排班、日程与工时账本。
和网页版共用同一套业务规则与备份格式，同一份数据在两端必须得出相同结论。

| 项目 | 值 |
| --- | --- |
| 桌面显示名 | 省心日历 |
| App Store 名称 | 省心日历-循环班表（Apple ID 6815659759） |
| Bundle ID | `com.wenjinliu.calenease` |
| SKU | `calenease-ios` |
| Xcode 工程 / Target / Scheme | `CalenEase.xcodeproj` / `CalenEase` / `CalenEase` |
| iCloud 容器 | `iCloud.com.wenjinliu.calenease` |

- **最低系统**：iOS 26（Liquid Glass、`Tab` 新标签栏都要求 26 起）
- **数据存储**：应用沙盒里的一份 JSON 文档，不需要账号，不上传服务器
- **法定节假日**：本机计算，内置与网页端 `lunar-typescript` 逐年核对过的农历表
- **备份**：JSON 字段与网页版完全一致，两端可以互相导入

## 目录结构

```
project.yml                     XcodeGen 工程定义（.xcodeproj 不入库）
Scripts/bootstrap.sh            本地生成并打开工程
CalenEase/
  App/                          入口、根标签栏、界面偏好
  Design/                       表面与材质封装、配色、班次色球
  Models/                       班次、标签、循环模板、每日记录、工时设置、数据文档
  Rules/                        日期与年度周期、法定节假日、循环生成、加班判定、基本工时
  Data/                         数据门面、外部 JSON 清洗与迁移、职业预设、备份
  Features/Calendar             日历、月历网格、逐日编辑、批量修改、循环排班
  Features/Agenda               事项（日 / 周视图）、日程编辑、倒数日、时间轴
  Features/Stats                工时
  Features/Settings             设置、班次与标签编辑、每月基本工时、备份、关于
Tests/CalenEaseTests/           排班、加班、节假日、日程的单元测试
```

## 本地开发

```bash
brew install xcodegen
./Scripts/bootstrap.sh --open
```

`.xcodeproj` 是生成物，不进版本库。改了 `project.yml` 或增删文件后重新跑一次即可。

## 表面与材质写在哪里

页面是系统分组灰底，内容分「底 → 卡片 → 格子」三层，靠系统分组背景色拉层次；
玻璃只留给真正浮在内容之上的东西（轻提示、悬浮控件）。这些封装都在
`CalenEase/Design/Surfaces.swift`：`card` / `insetSurface` / `floatingPill`，
iOS 26 的 Liquid Glass 系统 API 也只出现在这一个文件里。

## 数据为什么存成一份文档

排班的每一次修改都是对整份数据做变换——换一套循环会把生效日之后整段重排，
切换职业预设会重算班次、标签和模板。这跟网页版 `AppData` 的模型是同一回事，
所以 iOS 端同样按整份 `ScheduleDocument` 存取（Application Support 下的
`calenease.json`，合并写盘、原子替换），而不是拆成多张互相牵连的表。
好处是备份与网页端逐字段对齐，导入导出不需要任何转换层。

## CI

| Workflow | 触发 | 作用 |
| --- | --- | --- |
| `iOS Build & Test` | push main / PR / 手动 | 生成工程、模拟器编译、跑单元测试 |
| `App Icon Preview` | 图标文件 push / 手动 | Xcode 原生验证；第三方预览仅作非阻塞辅助 |
| `TestFlight` | 手动 / `v*` tag | 核对 App Store Connect 注册信息，归档、签名、上传 TestFlight；勾「只核对」则只列出 App / Bundle ID / SKU / iCloud 容器 |

TestFlight 需要的 Secrets 见 [`../docs/ios-release.md`](../docs/ios-release.md)。
图标源文件与验证规则见 [`../docs/app-icon-workflow.md`](../docs/app-icon-workflow.md)。

## 与网页版的关系

奖惩规则只有一套：法定节假日判定、每月基本工时推算、加班判定、循环生成，
都在 `Rules/` 下逐条对应 `app/lib/schedule.ts` 与 `app/lib/holidays.ts`，
`Tests/CalenEaseTests/` 就是照着 web 版 `tests/` 写的。

备份文件互通：iOS 导出的 JSON 与网页版结构一致（`{ app, version, exportedAt, data }`），
可以直接在网页端导入，反之亦然。

## 从「循环班表」改名过来

新 App 用的是新的 Bundle ID，和旧版是两个 App，系统不会把旧版沙盒里的数据带过来。
能接上的地方都接上了：

- **数据文件**：旧文件名 `shift-ledger.json` 在首次启动时原样改名为 `calenease.json`；
  改名失败就原地读旧文件，一条都不丢。
- **备份**：新备份叫 `calenease-auto-*` / `calenease-manual-*` / `calenease-safety-*`；
  旧名 `shift-ledger-*` 的备份照样列出、能恢复。导出的 JSON 结构不变（`app` 字段写 `calenease`，
  读的时候不看这个字段），所以旧版导出的备份、旧版 iCloud 云盘「循环班表」文件夹里的备份、
  网页版导出的备份，都可以在「设置 › 备份」里用「从文件导入」恢复。
- **通知**：新通知 ID 前缀 `calenease.`，重排时连旧前缀 `shiftledger.` 的一起撤掉。
- **界面偏好**（UserDefaults 键）没有带 App 名，原样沿用。
