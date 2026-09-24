# 中国法定节假日数据

公开入口：`https://wenjin-cloudbase-d1empq882391ac1-1311287495.ap-shanghai.app.tcloudbase.com/holidays/v1/index.json`

腾讯云默认 HTTP 域名实行 `no-store, no-cache, must-revalidate, max-age=0`；本接口接受该缓存策略，客户端按需读取，不依赖中间缓存。无须另绑域名。静态托管默认域名缺少规定的 UTF-8 Content-Type 和 CORS，因此此管线使用独立 HTTP 云函数。

数据唯一来源是 [NateScarlet/holiday-cn](https://github.com/NateScarlet/holiday-cn)（MIT）；取其 `master` 的一致快照，从 2007 年起读取所有已存在的 `YYYY.json`。不补全或修改源文件中的日期。源文件跨年日期留在原年份文件。`holidays/v1/` 保存已成功发布的精确 JSON，Git 提交历史可作回滚依据。

`scripts/holidays/build.py` 在发布前校验所有年份、日期、重复日、跨文件类型冲突和 `off` 天数异常。任一失败停止发布。内容无变化时沿用原字节及时间戳，不调用部署。成功后部署独立 HTTP 函数 `calenease-holidays-v1-http`，HTTP 网关路径 `/holidays/v1` 完整透传。函数包内的 `holidays/v1/` 与仓库目录相同；公开只读 `GET/HEAD`，响应 JSON UTF-8、CORS `*`、`Cache-Control: no-store`（网关会附加 `no-cache, must-revalidate, max-age=0`）。

工作流 [Update China holidays](../.github/workflows/update-holidays.yml) 北京时间周一 10:17 在 10 月 15 日至次年 1 月 31 日之间执行；其他时间每月 1 日 10:17 执行。GitHub 的排程可能延迟。HTTP 函数代码修改并推送到 `main` 也会触发部署。进入仓库 Actions → Update China holidays → Run workflow 可随时手动执行。需要仓库 Actions Secret `CLOUDBASE_API_KEY`，不得填入 App 或提交到仓库。

失败时 GitHub Actions 红灯并自动创建指派仓库拥有者的 issue；验证失败时尝试以当前 Git 文件回滚函数。每次变更的候选 JSON 保留为 Actions artifact 90 天，成功版本留在 Git 历史中。HTTP 网关当前接入方式为 DIRECT；若以后改为 CDN，须在发布后添加针对 index 和变更年份 URL 的刷新，并验证生效，再启用 CDN。
