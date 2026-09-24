import SwiftUI

/// 首页最下面的倒计时区。
struct CountdownSection: View {
    let onOpen: (Countdown?) -> Void

    @Environment(ScheduleStore.self) private var store

    var body: some View {
        let items = CountdownMath.sorted(store.document.countdowns, today: store.todayKey)
            .map { CountdownEntry(countdown: $0.0, status: $0.1) }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("倒数日").font(.headline)
                Spacer()
                Button { onOpen(nil) } label: {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 30, height: 30)
                        .background(Palette.card, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("新建倒数日")
            }
            .padding(.horizontal, 4)

            if items.isEmpty {
                Button { onOpen(nil) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "hourglass")
                            .font(.title3)
                            .foregroundStyle(Palette.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("记下重要的日子").font(.subheadline.weight(.semibold))
                            Text("生日、考试、入职纪念……倒着数或正着数都行。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .card(cornerRadius: 20, padding: 14)
                }
                .buttonStyle(.plain)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                          spacing: 10) {
                    ForEach(items) { item in
                        Button { onOpen(item.countdown) } label: {
                            CountdownCard(countdown: item.countdown, status: item.status)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct CountdownEntry: Identifiable {
    let countdown: Countdown
    let status: CountdownStatus
    var id: String { countdown.id }
}

/// 一张倒计时卡片：标题、大数字、说明。
struct CountdownCard: View {
    let countdown: Countdown
    let status: CountdownStatus

    var body: some View {
        let tone = Tone.event(countdown.color)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(countdown.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if countdown.pinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(tone.ink)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                if status.isToday {
                    Text(countdown.kind == .countdown ? "就是今天" : "第一天")
                        .font(.title2.weight(.bold))
                } else {
                    Text(status.caption)
                        .font(.caption.weight(.semibold))
                    Text("\(status.days)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("天")
                        .font(.caption.weight(.semibold))
                }
            }
            .foregroundStyle(tone.ink)
            Text(footnote)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(tone.fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var footnote: String {
        if let breakdown = status.breakdown, status.days >= 30 { return breakdown }
        var text = status.targetDate.replacingOccurrences(of: "-", with: ".")
        if countdown.repeatsYearly { text += " · 每年" }
        return text
    }
}

/// 新建 / 编辑倒数日。
struct CountdownEditorSheet: View {
    let original: Countdown?

    @Environment(ScheduleStore.self) private var store
    @Environment(\.showToast) private var showToast
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Countdown
    @State private var isConfirmingDelete = false

    init(original: Countdown?, today: String) {
        self.original = original
        _draft = State(initialValue: original ?? Countdown(date: today))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称，比如「生日」「入职」", text: $draft.title)
                        .font(.headline)
                    Picker("类型", selection: $draft.kind.animation(.snappy(duration: 0.25))) {
                        Text("倒数日 · 还有几天").tag(Countdown.Kind.countdown)
                        Text("正数日 · 已经几天").tag(Countdown.Kind.countUp)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    DatePicker(draft.kind == .countdown ? "目标日期" : "起始日期",
                               selection: dateBinding, displayedComponents: [.date])
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                    if draft.kind == .countdown {
                        Toggle("每年重复", isOn: $draft.repeatsYearly)
                        Toggle("当天提醒", isOn: $draft.remind)
                    }
                    Toggle("置顶", isOn: $draft.pinned)
                } footer: {
                    if draft.kind == .countdown && draft.repeatsYearly {
                        Text("生日、纪念日这类每年都有的日子，过了之后自动数到明年。")
                    }
                }

                Section("颜色") {
                    ColorPaletteRow(palette: AccentHex.eventPalette, selection: $draft.color)
                }

                Section("备注") {
                    TextField("写点什么", text: Binding(get: { draft.note ?? "" },
                                                    set: { draft.note = $0.isEmpty ? nil : $0 }),
                              axis: .vertical)
                        .lineLimit(1...4)
                }

                if original != nil {
                    Section {
                        Button(role: .destructive) { isConfirmingDelete = true } label: {
                            Label("删除", systemImage: "trash").foregroundStyle(.red)
                        }
                    }
                }
            }
            .pageBackground()
            .navigationTitle(original == nil ? "新建倒数日" : "编辑倒数日")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("删除「\(draft.title)」？", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    store.deleteCountdown(id: draft.id)
                    showToast("已删除", symbol: "trash")
                    dismiss()
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var dateBinding: Binding<Date> {
        Binding(get: { ScheduleCalendar.date(from: draft.date) ?? Date() },
                set: { draft.date = ScheduleCalendar.key($0) })
    }

    private func save() {
        var countdown = draft
        countdown.title = countdown.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if countdown.kind == .countUp {
            countdown.repeatsYearly = false
            countdown.remind = false
        }
        store.saveCountdown(countdown)
        if countdown.remind && store.document.reminders.countdownEnabled {
            Task { await NotificationScheduler.requestAuthorization() }
        }
        showToast(original == nil ? "已添加" : "已保存", symbol: "hourglass")
        dismiss()
    }
}
