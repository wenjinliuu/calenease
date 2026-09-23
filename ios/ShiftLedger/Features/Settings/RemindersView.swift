import SwiftUI

/// 设置 › 提醒。所有提醒集中在这一页，都是本机通知，在设备上排好，不经过服务器。
struct RemindersView: View {
    @Environment(ScheduleStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var isDenied = false

    private var document: ScheduleDocument { store.document }
    private var settings: ReminderSettings { document.reminders }
    private var workShifts: [ShiftDefinition] {
        document.orderedShifts.filter { !$0.isRest && $0.countsAsWork && !$0.startTime.isEmpty }
    }

    var body: some View {
        Form {
            if isDenied {
                Section {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    } label: {
                        Label("通知权限已关闭，点这里去系统设置打开", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Palette.orange)
                    }
                }
            }

            if document.features.shiftsEnabled {
                Section {
                    Toggle("上班前提醒", isOn: bind(\.shiftStartEnabled))
                    if settings.shiftStartEnabled {
                        Picker("提前", selection: bind(\.shiftStartMinutes)) {
                            ForEach([15, 30, 45, 60, 90, 120, 180], id: \.self) { minutes in
                                Text(ReminderPlanner.lead(minutes)).tag(minutes)
                            }
                        }
                        ForEach(workShifts) { shift in
                            Toggle(isOn: Binding(
                                get: { !settings.shiftStartExcluded.contains(shift.id) },
                                set: { included in
                                    store.updateReminders { reminders in
                                        reminders.shiftStartExcluded.removeAll { $0 == shift.id }
                                        if !included { reminders.shiftStartExcluded.append(shift.id) }
                                    }
                                })) {
                                HStack(spacing: 10) {
                                    ShiftOrb(shift: shift, size: 24)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(shift.name)
                                        Text(shift.fullRange)
                                            .font(.caption)
                                            .monospacedDigit()
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    Toggle("下班打卡提醒", isOn: bind(\.clockOutEnabled))
                    if settings.clockOutEnabled {
                        Picker("下班后", selection: bind(\.clockOutMinutes)) {
                            ForEach([0, 5, 10, 15, 30], id: \.self) { minutes in
                                Text(minutes == 0 ? "准点" : ReminderPlanner.lead(minutes)).tag(minutes)
                            }
                        }
                    }
                } header: {
                    Text("班次")
                } footer: {
                    Text("按日历上排好的班提醒；休息日不提醒。关掉某个班次，它就不发上班前提醒。")
                }
            }

            Section {
                Picker("新日程默认提醒", selection: bind(\.eventDefaultMinutes)) {
                    Text("不提醒").tag(Int?.none)
                    ForEach([0, 5, 10, 15, 30, 60], id: \.self) { minutes in
                        Text(EventEditorSheet.reminderLabel(minutes)).tag(Int?.some(minutes))
                    }
                }
                DatePicker("全天日程提醒时间", selection: clockBinding(\.allDayEventTime),
                           displayedComponents: [.hourAndMinute])
            } header: {
                Text("日程")
            } footer: {
                Text("每条日程可以在编辑时单独改提醒。")
            }

            Section {
                Toggle("倒数日当天提醒", isOn: bind(\.countdownEnabled))
                if settings.countdownEnabled {
                    DatePicker("提醒时间", selection: clockBinding(\.countdownTime),
                               displayedComponents: [.hourAndMinute])
                }
            } header: {
                Text("倒数日")
            } footer: {
                Text("提醒都是本机通知，在这台设备上排好，不经过任何服务器。")
            }
        }
        .pageBackground()
        .navigationTitle("提醒")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .task { isDenied = await NotificationScheduler.isDenied() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { isDenied = await NotificationScheduler.isDenied() }
        }
    }

    /// 改提醒设置；打开任何一项时顺手请求通知权限。
    private func bind<Value>(_ keyPath: WritableKeyPath<ReminderSettings, Value>) -> Binding<Value> {
        Binding(get: { settings[keyPath: keyPath] }, set: { newValue in
            store.updateReminders { $0[keyPath: keyPath] = newValue }
            if (newValue as? Bool) == true {
                Task {
                    await NotificationScheduler.requestAuthorization()
                    isDenied = await NotificationScheduler.isDenied()
                }
            }
        })
    }

    private func clockBinding(_ keyPath: WritableKeyPath<ReminderSettings, String>) -> Binding<Date> {
        Binding(get: {
            EventClock.date(key: ScheduleCalendar.todayKey, time: settings[keyPath: keyPath])
        }, set: { date in
            let text = EventClock.split(date).time
            store.updateReminders { $0[keyPath: keyPath] = text }
        })
    }
}
