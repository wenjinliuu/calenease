import SwiftUI

/// 关于页：版本、隐私政策、反馈入口和免责声明。
struct AboutView: View {
    private var version: String {
        let marketing = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(marketing) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("省心日历").font(.title3.weight(.bold))
                    Text("排班、日程、工时一本账，专门为不按星期工作的人设计：自定义班次与循环模板，工时与加班分别统计，自动标注放假与调休。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                LabeledContent("版本", value: version)
            }

            Section("链接") {
                Link(destination: URL(string: "https://wenjinliuu.github.io/calenease/privacy/")!) {
                    Label("隐私政策", systemImage: "hand.raised")
                }
                Link(destination: URL(string: "https://wenjinliuu.github.io/calenease/support/")!) {
                    Label("反馈与支持", systemImage: "bubble.left.and.bubble.right")
                }
                Link(destination: URL(string: "https://wenjinliuu.github.io/calenease/")!) {
                    Label("网页版", systemImage: "safari")
                }
            }

            Section {
                Text("本工具用于个人排班记录和工时预估，最终工时以公司考勤记录和适用制度为准。放假与调休按国务院每年公布的安排（联网更新），尚未公布的年份按法定节假日推算。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("免责声明")
            }
        }
        .pageBackground()
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }
}
