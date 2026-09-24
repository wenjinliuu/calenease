import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "技术支持｜省心日历",
  description: "省心日历技术支持：常见问题、使用说明与联系方式。",
};

const SUPPORT_EMAIL = "wenjinliuu@outlook.com";

/**
 * 技术支持页。和隐私政策共用同一套纯文本排版；
 * 第一职责是「怎么找到人」，所以联系方式放在最前面。
 */
export default function Support() {
  return (
    <main className="legal-page">
      <h1>省心日历 技术支持</h1>
      <p className="legal-meta">使用说明、常见问题与联系方式</p>

      <h2>联系我们</h2>
      <p>
        邮件是唯一的支持渠道，通常 1 至 3 个工作日内回复：
        {" "}
        <a href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a>
      </p>
      <p>
        为了方便定位问题，建议附上设备型号、iOS 版本、应用版本号（在「设置 → 关于」里查看），
        以及问题的截图或复现步骤。
      </p>

      <h2>常见问题</h2>
      <div className="support-faq">
        <details>
          <summary>怎么快速排好一整段时间的班？</summary>
          <p>
            点日历页右上角的「循环排班」，选一个模板（4 天、8 天、12 天一轮）或自己一天天拼出循环，
            设好生效日即可。生效日之前的记录不变，之后按循环自动生成，往后翻年份也会自动延续。
          </p>
        </details>
        <details>
          <summary>某一天要临时换班，或者一天上两种班？</summary>
          <p>
            点日历上那一天，在弹出的面板里换「主要班次」。一天有两种班时，点「添加次要班次」再选一个，
            日历格子上会并排显示两枚色标。单独改某一天不会打断后面的循环。
          </p>
        </details>
        <details>
          <summary>右上角的「休」「班」是怎么来的？</summary>
          <p>
            来自国务院每年公布的放假与调休安排（数据整理自开源项目 holiday-cn）。应用联网时会自动更新，
            下一年的安排通常在年底前后公布。每月基本工时也按这份安排推算：放假的日子不算，周末调休上班的日子算。
            还没公布安排的年份按法定节假日推算。
          </p>
        </details>
        <details>
          <summary>基本工时和公司考勤对不上？</summary>
          <p>
            在「设置 → 每月基本工时」里可以逐月手动修正，修正后以你填的数为准。应用里的工时与加班只是个人预估，
            最终以公司考勤记录和适用制度为准。
          </p>
        </details>
        <details>
          <summary>数据存在哪里？换手机怎么迁移？</summary>
          <p>
            所有记录只保存在你的手机上，没有账号，也不会上传到任何服务器。「设置 → 备份与恢复」里可以打开
            自动备份并选择备份到 iCloud 云盘；换手机后登录同一个 Apple 账户，在同一页选一份备份恢复即可。
            也可以导出 JSON 文件自己保存，在新设备上「从文件导入」。
          </p>
          <p>卸载应用会删除手机上的全部记录，卸载或换机前请先确认有备份。</p>
        </details>
        <details>
          <summary>iCloud 备份提示用不了？</summary>
          <p>
            请确认已登录 Apple 账户，并在「设置 → Apple 账户 → iCloud → iCloud 云盘」中打开 iCloud 云盘、
            允许「省心日历」使用。iCloud 暂时用不了时，备份会先存在手机本机，不会丢。
          </p>
        </details>
        <details>
          <summary>可以提功能建议吗？</summary>
          <p>非常欢迎，直接发到上面的邮箱。反馈会逐条查看，被采纳的改动会在后续版本中更新。</p>
        </details>
      </div>

      <h2>相关链接</h2>
      <p>
        <a href="../privacy/">隐私政策</a>
      </p>
    </main>
  );
}
