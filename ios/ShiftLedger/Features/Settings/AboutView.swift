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
                    Text("循环班表").font(.title3.weight(.bold))
                    Text("专门为不按星期工作的人设计的个人循环班表：自定义班次与循环模板，工时与加班分别统计，自动识别法定节假日。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                LabeledContent("版本", value: version)
            }

            Section("链接") {
                Link(destination: URL(string: "https://wenjinliuu.github.io/shift-ledger/privacy/")!) {
                    Label("隐私政策", systemImage: "hand.raised")
                }
                Link(destination: URL(string: "https://github.com/wenjinliuu/shift-ledger/issues")!) {
                    Label("反馈与支持", systemImage: "bubble.left.and.bubble.right")
                }
                Link(destination: URL(string: "https://wenjinliuu.github.io/shift-ledger/")!) {
                    Label("网页版", systemImage: "safari")
                }
            }

            Section {
                Text("本工具用于个人排班记录和工时预估，最终工时以公司考勤记录和适用制度为准。法定节假日按《全国年节及纪念日放假办法》规定的 13 个法定日判定，不含每年另行公布的调休与补班。")
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
