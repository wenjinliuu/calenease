"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import type {
  ChangeEvent,
  CSSProperties,
  ReactNode,
  TouchEvent as ReactTouchEvent,
} from "react";
import {
  statutoryHolidayName,
  statutoryHolidayShortName,
} from "./lib/holidays";
import {
  DATA_VERSION,
  ACCENT_COLORS,
  STORAGE_DATA,
  STORAGE_LEGACY_RECORDS,
  STORAGE_LEGACY_SETTINGS,
  SHIFT_COLORS,
  TAG_COLORS,
  applyCareerPreset,
  calculateOvertime,
  calculateShiftDuration,
  createDefaultData,
  gradientEndForColor,
  getAnnualCycle,
  makeId,
  materializeCycleYear,
  migrateLegacyData,
  normalizeAppData,
  replaceCycleFromDate,
  type ActiveCycle,
  type AnnualCycle,
  type AnnualCycleMonth,
  type AppData,
  type CareerPreset,
  type CycleTemplate,
  type DayRecord,
  type DutyTag,
  type Shift,
  type StatisticsPeriod,
  type WorkSystem,
} from "./lib/schedule";

const APP_VERSION = "1.0.0";
const PRIVACY_URL = "https://wenjinliuu.github.io/calenease/privacy/";
const SUPPORT_URL = "https://github.com/wenjinliuu/calenease/issues";

type View = "calendar" | "stats" | "settings";
type StatsScope = "month" | "year";
type EntityEditor =
  | { type: "shift"; value?: Shift }
  | { type: "tag"; value?: DutyTag }
  | null;

const WEEKDAYS = ["一", "二", "三", "四", "五", "六", "日"];
const MONTH_LABELS = [
  "一月",
  "二月",
  "三月",
  "四月",
  "五月",
  "六月",
  "七月",
  "八月",
  "九月",
  "十月",
  "十一月",
  "十二月",
];
const CAREERS: { id: CareerPreset; name: string; detail: string }[] = [
  { id: "manufacturing", name: "制造业 / 半导体", detail: "白夜班与连续倒班" },
  { id: "medical", name: "医疗护理", detail: "白班、小夜、大夜与职责标签" },
  { id: "transport", name: "交通运输", detail: "铁路、地铁、机场等" },
  { id: "safety", name: "公共安全", detail: "安保、消防与值守" },
  { id: "service", name: "服务业", detail: "酒店、物流与轮值" },
  { id: "custom", name: "其他 / 自定义", detail: "从自己的班次开始" },
];
const CAREER_FEATURES: Record<CareerPreset, string[]> = {
  manufacturing: ["白夜轮换", "12 小时班", "综合工时"],
  medical: ["大小夜班", "责班 / 门诊示例", "职责标签"],
  transport: ["早中晚班", "连续轮值", "自定义循环"],
  safety: ["白夜值守", "备班标签", "连续倒班"],
  service: ["早中晚班", "灵活轮值", "自定义班次"],
  custom: ["从零开始", "完全自定义", "不限制功能"],
};
const SYSTEM_LABELS: Record<WorkSystem, string> = {
  standard: "标准工时",
  comprehensive: "综合计算工时",
  irregular: "不定时工时",
  custom: "自定义",
  manual: "不清楚 / 仅手动记录",
};
const PERIOD_LABELS: Record<StatisticsPeriod, string> = {
  week: "周",
  month: "月",
  quarter: "季度",
  halfYear: "半年",
  year: "年度",
  custom: "自定义周期（暂按年度）",
};

function pad(value: number) {
  return String(value).padStart(2, "0");
}
function dateKey(date: Date) {
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}
function parseDate(key: string) {
  const [year, month, day] = key.split("-").map(Number);
  return new Date(year, month - 1, day);
}
function compactHours(value: number) {
  return Number.isInteger(value) ? String(value) : value.toFixed(1);
}
function compactClock(time: string, asEnd = false) {
  if (!time) return "";
  const [hour, minute] = time.split(":").map(Number);
  if (!Number.isFinite(hour) || !Number.isFinite(minute)) return "";
  if (asEnd && hour === 0 && minute === 0) return "24";
  return compactHours(Math.round((hour + minute / 60) * 2) / 2);
}
function compactShiftRange(shift: Shift) {
  if (!shift.startTime || !shift.endTime) return "";
  const endAs24 = !shift.crossesMidnight && shift.startTime !== "00:00";
  return `${compactClock(shift.startTime)}~${compactClock(shift.endTime, endAs24)}`;
}
function fullShiftRange(shift: Shift) {
  if (!shift.startTime || !shift.endTime) return "";
  return `${shift.startTime}–${shift.endTime}`;
}
function orderedShifts(shifts: Shift[]) {
  const order = [
    "shift-day",
    "shift-night",
    "shift-rest",
    "shift-leave",
    "shift-morning",
    "shift-middle",
    "shift-late",
    "shift-small-night",
    "shift-big-night",
    "shift-medical-duty",
    "shift-medical-clinic",
    "shift-standby",
  ];
  const rank = new Map(order.map((id, index) => [id, index]));
  return [...shifts].sort(
    (a, b) => (rank.get(a.id) ?? 99) - (rank.get(b.id) ?? 99),
  );
}
function getCalendarDays(year: number, month: number) {
  const leading = (new Date(year, month, 1).getDay() + 6) % 7;
  const days = new Date(year, month + 1, 0).getDate();
  return [
    ...Array(leading).fill(null),
    ...Array.from({ length: days }, (_, index) => index + 1),
  ];
}
function inclusiveDateRange(first: string, second: string) {
  const start = parseDate(first < second ? first : second);
  const end = parseDate(first < second ? second : first);
  const dates: string[] = [];
  for (
    const cursor = new Date(start);
    cursor <= end;
    cursor.setDate(cursor.getDate() + 1)
  )
    dates.push(dateKey(cursor));
  return dates;
}
function colorStyle(color: string) {
  return {
    "--entity-color": color,
    "--entity-color-2": gradientEndForColor(color),
  } as CSSProperties;
}

function estimateMonthlyTarget(
  year: number,
  month: number,
  dailyStandard: number,
) {
  let workdays = 0;
  const cursor = new Date(year, month, 1);
  while (cursor.getMonth() === month) {
    const day = cursor.getDay();
    if (day !== 0 && day !== 6 && !statutoryHolidayName(dateKey(cursor)))
      workdays += 1;
    cursor.setDate(cursor.getDate() + 1);
  }
  return workdays * dailyStandard;
}
function getMonthlyTarget(data: AppData, year: number, month: number) {
  const key = `${year}-${pad(month + 1)}`;
  const override = data.targets[key];
  return Number.isFinite(override)
    ? override
    : estimateMonthlyTarget(
        year,
        month,
        data.work.system === "comprehensive" ? 8 : data.work.dailyStandard,
      );
}
function reportingCycleForMonth(data: AppData, year: number, month: number) {
  return getAnnualCycle(
    year,
    month,
    data.work.system === "comprehensive" ? data.work.annualStartMonth : 1,
  );
}
function getAnnualTarget(data: AppData, months: AnnualCycleMonth[]) {
  return months.reduce(
    (sum, item) => sum + getMonthlyTarget(data, item.year, item.month),
    0,
  );
}
function recordsForMonths(records: DayRecord[], months: AnnualCycleMonth[]) {
  const keys = new Set(months.map((item) => item.key));
  return records.filter((record) => keys.has(record.date.slice(0, 7)));
}
function getPeriodOvertime(
  records: DayRecord[],
  data: AppData,
  months: AnnualCycleMonth[],
) {
  if (data.work.system === "custom" && data.work.customRule === "monthly")
    return months.reduce((sum, item) => {
      const monthRecords = records.filter((record) =>
        record.date.startsWith(item.key),
      );
      return sum + calculateOvertime(monthRecords, data.work, 0);
    }, 0);
  if (data.work.system !== "comprehensive")
    return calculateOvertime(records, data.work, getAnnualTarget(data, months));
  if (data.work.period === "month")
    return months.reduce((sum, item) => {
      const monthRecords = records.filter((record) =>
        record.date.startsWith(item.key),
      );
      return (
        sum +
        calculateOvertime(
          monthRecords,
          data.work,
          getMonthlyTarget(data, item.year, item.month),
        )
      );
    }, 0);
  if (data.work.period === "quarter" || data.work.period === "halfYear") {
    const size = data.work.period === "quarter" ? 3 : 6;
    let overtime = 0;
    for (let start = 0; start < 12; start += size) {
      const periodMonths = months.slice(start, start + size);
      const periodRecords = recordsForMonths(records, periodMonths);
      const target = getAnnualTarget(data, periodMonths);
      overtime += calculateOvertime(periodRecords, data.work, target);
    }
    return overtime;
  }
  if (data.work.period === "week")
    return calculateOvertime(
      records,
      {
        ...data.work,
        system: "standard",
        standardDailyEnabled: false,
        standardWeeklyEnabled: true,
      },
      0,
    );
  return calculateOvertime(records, data.work, getAnnualTarget(data, months));
}

function completedByDate(records: DayRecord[], todayKey: string) {
  return records.filter(
    (record) => record.planned && (record.completed || record.date < todayKey),
  );
}

function comprehensiveScopeForMonth(
  data: AppData,
  year: number,
  month: number,
  records: DayRecord[],
  todayKey: string,
) {
  const cycle = reportingCycleForMonth(data, year, month);
  const activeIndex = cycle.months.findIndex(
    (item) => item.year === year && item.month === month,
  );
  let scopeMonths = cycle.months.slice(activeIndex, activeIndex + 1);
  let label = `${month + 1}月`;
  if (data.work.period === "quarter") {
    const start = Math.floor(activeIndex / 3) * 3;
    scopeMonths = cycle.months.slice(start, start + 3);
    label = `第 ${Math.floor(activeIndex / 3) + 1} 季度`;
  } else if (data.work.period === "halfYear") {
    const start = activeIndex < 6 ? 0 : 6;
    scopeMonths = cycle.months.slice(start, start + 6);
    label = start === 0 ? "上半年" : "下半年";
  } else if (data.work.period === "year" || data.work.period === "custom") {
    scopeMonths = cycle.months;
    label =
      data.work.period === "year"
        ? cycle.label
        : `${cycle.label}自定义周期`;
  }
  const scoped = recordsForMonths(records, scopeMonths);
  if (data.work.period === "week") {
    const monthRecords = records.filter((record) =>
      record.date.startsWith(`${year}-${pad(month + 1)}`),
    );
    const weeklySettings = {
      ...data.work,
      system: "standard" as const,
      standardDailyEnabled: false,
      standardWeeklyEnabled: true,
    };
    return {
      label: `${month + 1}月各周`,
      projected: calculateOvertime(monthRecords, weeklySettings, 0),
      actual: calculateOvertime(
        completedByDate(monthRecords, todayKey),
        weeklySettings,
        0,
      ),
    };
  }
  const target = getAnnualTarget(data, scopeMonths);
  return {
    label,
    projected: calculateOvertime(scoped, data.work, target),
    actual: calculateOvertime(
      completedByDate(scoped, todayKey),
      data.work,
      target,
    ),
  };
}

function overtimeForCalendarMonth(
  data: AppData,
  year: number,
  month: number,
  monthRecords: DayRecord[],
  yearRecords: DayRecord[],
  todayKey: string,
) {
  if (!data.work.trackHours || !data.work.trackOvertime)
    return { label: "", projected: 0, actual: 0 };
  if (data.work.system === "comprehensive")
    return comprehensiveScopeForMonth(data, year, month, yearRecords, todayKey);
  const target = getMonthlyTarget(data, year, month);
  return {
    label: `${month + 1}月`,
    projected: calculateOvertime(monthRecords, data.work, target),
    actual: calculateOvertime(
      completedByDate(monthRecords, todayKey),
      data.work,
      target,
    ),
  };
}

function canAllocateOvertimeByMonth(data: AppData) {
  return (
    data.work.trackOvertime &&
    (data.work.system !== "comprehensive" ||
      data.work.period === "month" ||
      data.work.period === "week")
  );
}

function materializeReportingYears(
  data: AppData,
  year: number,
  month: number,
) {
  const cycle = reportingCycleForMonth(data, year, month);
  return [...new Set([cycle.startYear, cycle.endYear])].reduce(
    (current, cycleYear) => materializeCycleYear(current, cycleYear),
    data,
  );
}

function Icon({ name }: { name: string }) {
  const paths: Record<string, ReactNode> = {
    calendar: (
      <>
        <rect x="3.5" y="5.5" width="17" height="15" rx="3" />
        <path d="M7.5 3.5v4M16.5 3.5v4M3.5 10h17M8 14h.01M12 14h.01M16 14h.01M8 17.5h.01M12 17.5h.01M16 17.5h.01" />
      </>
    ),
    stats: (
      <>
        <path d="M4 19V10M10 19V5M16 19v-7M22 19H2" />
      </>
    ),
    settings: (
      <>
        <circle cx="12" cy="12" r="3" />
        <path d="M19 12a7 7 0 1 1-14 0 7 7 0 0 1 14 0ZM12 2v3M12 19v3M2 12h3M19 12h3" />
      </>
    ),
    spark: (
      <path d="m12 3 1.5 5.5L19 10l-5.5 1.5L12 17l-1.5-5.5L5 10l5.5-1.5L12 3Z" />
    ),
    check: <path d="m5 12 4 4L19 6" />,
    trash: (
      <>
        <path d="M4 7h16M9 7V4h6v3M7 7l1 13h8l1-13M10 11v5M14 11v5" />
      </>
    ),
    upload: (
      <>
        <path d="M12 16V4m0 0L7 9m5-5 5 5" />
        <path d="M5 14v6h14v-6" />
      </>
    ),
    download: (
      <>
        <path d="M12 4v12m0 0-5-5m5 5 5-5" />
        <path d="M5 20h14" />
      </>
    ),
    plus: <path d="M12 5v14M5 12h14" />,
    tag: <path d="M20 13 13 20l-9-9V4h7l9 9ZM8 8h.01" />,
    edit: (
      <>
        <path d="m4 16-.8 4 4-.8L18 8.4 14.6 5 4 16Z" />
        <path d="m12.8 6.8 3.4 3.4" />
      </>
    ),
  };
  return (
    <svg
      className="app-icon"
      aria-hidden="true"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      {paths[name]}
    </svg>
  );
}

function MonthSwitch({
  year,
  month,
  onChange,
  onCurrent,
  compact = false,
}: {
  year: number;
  month: number;
  onChange: (delta: number) => void;
  onCurrent: () => void;
  compact?: boolean;
}) {
  return (
    <div
      className={`month-switch glass-control embedded-month-switch${compact ? " compact" : ""}`}
      aria-label="选择月份"
    >
      <button aria-label="上个月" onClick={() => onChange(-1)}>
        ‹
      </button>
      <button
        aria-label="回到本月"
        className="current-month"
        onClick={onCurrent}
      >
        <small>{year}年</small>
        <strong>{month + 1}月</strong>
      </button>
      <button aria-label="下个月" onClick={() => onChange(1)}>
        ›
      </button>
    </div>
  );
}

function PeriodRange({
  cycle,
  year,
  month,
  annual,
}: {
  cycle: AnnualCycle;
  year: number;
  month: number;
  annual: boolean;
}) {
  return (
    <div className="period-range" aria-label={annual ? cycle.label : `${year}年${month + 1}月`}>
      <small>{annual ? "年度工时范围" : "当前统计月份"}</small>
      {annual ? (
        <strong>
          <span>
            {cycle.startYear}.{pad(cycle.startMonth + 1)}
          </span>
          <i>—</i>
          <span>
            {cycle.endYear}.{pad(cycle.endMonth + 1)}
          </span>
        </strong>
      ) : (
        <strong>
          {year}.{pad(month + 1)}
        </strong>
      )}
    </div>
  );
}

export default function Home() {
  const today = useMemo(() => new Date(), []);
  const todayKey = dateKey(today);
  const [view, setView] = useState<View>("calendar");
  const [data, setData] = useState<AppData>(createDefaultData);
  const [selectedMonth, setSelectedMonth] = useState(
    new Date(today.getFullYear(), today.getMonth(), 1),
  );
  const [selectedDate, setSelectedDate] = useState<string | null>(null);
  const [showGenerator, setShowGenerator] = useState(false);
  const [batchMode, setBatchMode] = useState(false);
  const [batchDates, setBatchDates] = useState<string[]>([]);
  const [showBatchEditor, setShowBatchEditor] = useState(false);
  const [ready, setReady] = useState(false);
  const [toast, setToast] = useState("");

  useEffect(() => {
    const timer = window.setTimeout(() => {
      try {
        const modern = window.localStorage.getItem(STORAGE_DATA);
        if (modern) {
          const normalized = normalizeAppData(JSON.parse(modern));
          setData(
            materializeReportingYears(
              normalized,
              today.getFullYear(),
              today.getMonth(),
            ),
          );
        }
        else {
          const legacySettings = window.localStorage.getItem(
            STORAGE_LEGACY_SETTINGS,
          );
          const legacyRecords = window.localStorage.getItem(
            STORAGE_LEGACY_RECORDS,
          );
          const migrated = migrateLegacyData(
            legacySettings ? JSON.parse(legacySettings) : undefined,
            legacyRecords ? JSON.parse(legacyRecords) : [],
          );
          setData(
            materializeReportingYears(
              migrated,
              today.getFullYear(),
              today.getMonth(),
            ),
          );
        }
      } catch {
        setData(createDefaultData());
      }
      setReady(true);
    }, 0);
    return () => window.clearTimeout(timer);
  }, [today]);
  useEffect(() => {
    if (ready) window.localStorage.setItem(STORAGE_DATA, JSON.stringify(data));
  }, [data, ready]);

  const year = selectedMonth.getFullYear();
  const month = selectedMonth.getMonth();
  const monthKey = `${year}-${pad(month + 1)}`;
  const monthRecords = useMemo(
    () => data.records.filter((record) => record.date.startsWith(monthKey)),
    [data.records, monthKey],
  );
  const shifts = useMemo(
    () => new Map(data.shifts.map((shift) => [shift.id, shift])),
    [data.shifts],
  );
  const tags = useMemo(
    () => new Map(data.tags.map((tag) => [tag.id, tag])),
    [data.tags],
  );
  function notify(message = "已保存") {
    setToast(message);
    window.setTimeout(() => setToast(""), 1800);
  }
  function changeMonth(delta: number) {
    setSelectedMonth((value) => {
      const next = new Date(value.getFullYear(), value.getMonth() + delta, 1);
      setData((current) =>
        materializeReportingYears(
          current,
          next.getFullYear(),
          next.getMonth(),
        ),
      );
      return next;
    });
  }
  function goToCurrentMonth() {
    const next = new Date(today.getFullYear(), today.getMonth(), 1);
    setData((current) =>
      materializeReportingYears(current, next.getFullYear(), next.getMonth()),
    );
    setSelectedMonth(next);
  }
  function changeView(nextView: View) {
    setView(nextView);
    window.requestAnimationFrame(() => {
      window.scrollTo({ top: 0, left: 0, behavior: "auto" });
    });
  }
  function saveRecord(record: DayRecord) {
    setData((current) => ({
      ...current,
      records: [
        ...current.records.filter((item) => item.date !== record.date),
        record,
      ].sort((a, b) => a.date.localeCompare(b.date)),
    }));
    notify();
  }
  function setRest(date: string) {
    const rest = data.shifts.find((shift) => shift.isRest) ?? data.shifts[0];
    if (!rest) return;
    saveRecord({
      date,
      shiftId: rest.id,
      hours: 0,
      tagIds: [],
      completed: false,
      planned: true,
      source: "manual",
    });
    setSelectedDate(null);
  }
  function toggleBatchDate(key: string) {
    if (!batchDates.length) setBatchDates([key]);
    else {
      setBatchDates(inclusiveDateRange(batchDates[0], key));
      setShowBatchEditor(true);
    }
  }
  function updateBatchRecords(shiftId: string, hours: number) {
    const selected = new Set(batchDates);
    const updates = batchDates.map((date) => ({
      date,
      shiftId,
      hours,
      tagIds: [],
      planned: true,
      completed: false,
      source: "manual" as const,
    }));
    setData((current) => ({
      ...current,
      records: [
        ...current.records.filter((record) => !selected.has(record.date)),
        ...updates,
      ].sort((a, b) => a.date.localeCompare(b.date)),
    }));
    setShowBatchEditor(false);
    setBatchMode(false);
    setBatchDates([]);
    notify(`已修改 ${updates.length} 天`);
  }
  function activateCycle(cycle: ActiveCycle, saveTemplate: boolean) {
    setData((current) => {
      const reportingCycle = reportingCycleForMonth(current, year, month);
      let next = replaceCycleFromDate(
        current,
        cycle,
        Math.max(
          reportingCycle.endYear,
          Number(cycle.startDate.slice(0, 4)),
        ),
      );
      if (
        saveTemplate &&
        !next.cycleTemplates.some(
          (template) =>
            template.name === cycle.name &&
            template.shiftIds.join() === cycle.shiftIds.join(),
        )
      )
        next = {
          ...next,
          cycleTemplates: [
            ...next.cycleTemplates,
            {
              id: makeId("template"),
              name: cycle.name,
              caption: cycle.shiftIds
                .map(
                  (id) =>
                    current.shifts.find((shift) => shift.id === id)
                      ?.shortName ?? "?",
                )
                .join(" "),
              shiftIds: cycle.shiftIds,
              category: "custom",
              builtIn: false,
            },
          ],
        };
      return next;
    });
    setShowGenerator(false);
    notify("新循环已生效");
  }
  const navItems: { id: View; label: string; icon: string }[] = [
    { id: "calendar", label: "日历", icon: "calendar" },
    { id: "stats", label: "统计", icon: "stats" },
    { id: "settings", label: "设置", icon: "settings" },
  ];
  if (!ready) return <main className="loading-screen">正在整理你的班次…</main>;

  return (
    <main className="app-shell">
      <div className="ambient ambient-one" />
      <div className="ambient ambient-two" />
      <aside className="side-nav glass-panel">
        <div className="brand-mark">
          <Icon name="spark" />
        </div>
        <div className="brand-copy">
          <strong>省心日历</strong>
          <span>不按星期工作的个人班表</span>
        </div>
        <nav>
          {navItems.map((item) => (
            <button
              key={item.id}
              className={view === item.id ? "active" : ""}
              onClick={() => changeView(item.id)}
            >
              <span className="nav-icon">
                <Icon name={item.icon} />
              </span>
              {item.label}
            </button>
          ))}
        </nav>
        <div className="privacy-note">
          <span>●</span> 数据仅保存在本机
        </div>
      </aside>
      <section className="content-wrap">
        {view === "calendar" && (
          <CalendarView
            year={year}
            month={month}
            data={data}
            records={monthRecords}
            shifts={shifts}
            tags={tags}
            todayKey={todayKey}
            onOpenDate={setSelectedDate}
            onGenerate={() => setShowGenerator(true)}
            batchMode={batchMode}
            batchDates={batchDates}
            onToggleBatchMode={() => {
              setBatchMode((value) => !value);
              setBatchDates([]);
            }}
            onToggleBatchDate={toggleBatchDate}
            onChangeMonth={changeMonth}
            onGoToCurrentMonth={goToCurrentMonth}
          />
        )}
        {view === "stats" && (
          <StatsView
            year={year}
            month={month}
            data={data}
            todayKey={todayKey}
            onChangeMonth={changeMonth}
            onGoToCurrentMonth={goToCurrentMonth}
          />
        )}
        {view === "settings" && (
          <SettingsView
            data={data}
            setData={setData}
            activeYear={year}
            activeMonth={month}
            onOpenGenerator={() => setShowGenerator(true)}
            notify={notify}
          />
        )}
      </section>
      <nav className="bottom-nav glass-panel">
        {navItems.map((item) => (
          <button
            key={item.id}
            className={view === item.id ? "active" : ""}
            onClick={() => changeView(item.id)}
          >
            <span>
              <Icon name={item.icon} />
            </span>
            {item.label}
          </button>
        ))}
      </nav>
      {selectedDate && (
        <DayEditor
          date={selectedDate}
          record={data.records.find((record) => record.date === selectedDate)}
          data={data}
          onClose={() => setSelectedDate(null)}
          onSave={(record) => {
            saveRecord(record);
            setSelectedDate(null);
          }}
          onRest={() => setRest(selectedDate)}
        />
      )}
      {showGenerator && (
        <ScheduleGenerator
          data={data}
          initialYear={year}
          onClose={() => setShowGenerator(false)}
          onGenerate={activateCycle}
        />
      )}
      {showBatchEditor && (
        <BatchEditor
          dates={batchDates}
          data={data}
          onClose={() => {
            setShowBatchEditor(false);
            setBatchDates([]);
          }}
          onSave={updateBatchRecords}
        />
      )}
      {toast && (
        <div className="toast">
          <Icon name="check" /> {toast}
        </div>
      )}
    </main>
  );
}

function CalendarView({
  year,
  month,
  data,
  records,
  shifts,
  tags,
  todayKey,
  onOpenDate,
  onGenerate,
  batchMode,
  batchDates,
  onToggleBatchMode,
  onToggleBatchDate,
  onChangeMonth,
  onGoToCurrentMonth,
}: {
  year: number;
  month: number;
  data: AppData;
  records: DayRecord[];
  shifts: Map<string, Shift>;
  tags: Map<string, DutyTag>;
  todayKey: string;
  onOpenDate: (key: string) => void;
  onGenerate: () => void;
  batchMode: boolean;
  batchDates: string[];
  onToggleBatchMode: () => void;
  onToggleBatchDate: (key: string) => void;
  onChangeMonth: (delta: number) => void;
  onGoToCurrentMonth: () => void;
}) {
  const recordMap = useMemo(
    () => new Map(records.map((record) => [record.date, record])),
    [records],
  );
  const touchStart = useRef<{ x: number; y: number } | null>(null);
  const motionTimer = useRef<number | null>(null);
  const [monthMotion, setMonthMotion] = useState("");
  const calendarDays = useMemo(
    () => getCalendarDays(year, month),
    [year, month],
  );
  const batchDateSet = useMemo(() => new Set(batchDates), [batchDates]);
  const workRecords = records.filter(
    (record) => shifts.get(record.shiftId)?.countsAsWork,
  );
  const restDays = records.filter(
    (record) => shifts.get(record.shiftId)?.isRest,
  ).length;
  const completed = completedByDate(workRecords, todayKey);
  const projectedHours = workRecords.reduce(
    (sum, record) => sum + record.hours,
    0,
  );
  const actualHours = completed.reduce((sum, record) => sum + record.hours, 0);
  const monthlyBasicHours = getMonthlyTarget(data, year, month);
  const allWorkRecords = data.records.filter((record) =>
    shifts.get(record.shiftId)?.countsAsWork,
  );
  const overtimeSummary = overtimeForCalendarMonth(
    data,
    year,
    month,
    workRecords,
    allWorkRecords,
    todayKey,
  );
  const upcoming = records.find(
    (record) =>
      record.date >= todayKey && shifts.get(record.shiftId)?.countsAsWork,
  );
  function touchStartHandler(event: ReactTouchEvent<HTMLElement>) {
    if (event.touches.length === 1 && !batchMode)
      touchStart.current = {
        x: event.touches[0].clientX,
        y: event.touches[0].clientY,
      };
  }
  function touchEndHandler(event: ReactTouchEvent<HTMLElement>) {
    if (!touchStart.current || batchMode) return;
    const dx = event.changedTouches[0].clientX - touchStart.current.x;
    const dy = event.changedTouches[0].clientY - touchStart.current.y;
    touchStart.current = null;
    if (Math.abs(dx) >= 55 && Math.abs(dx) > Math.abs(dy) * 1.25) {
      const direction = dx < 0 ? 1 : -1;
      if (motionTimer.current) window.clearTimeout(motionTimer.current);
      onChangeMonth(direction);
      setMonthMotion(direction > 0 ? "slide-in-right" : "slide-in-left");
      motionTimer.current = window.setTimeout(() => {
        setMonthMotion("");
        motionTimer.current = null;
      }, 145);
    }
  }
  return (
    <div className="calendar-page">
      <div className="calendar-layout">
        <section
          className="calendar-panel glass-panel"
          onTouchStart={touchStartHandler}
          onTouchEnd={touchEndHandler}
        >
          <div className="calendar-toolbar">
            <MonthSwitch
              year={year}
              month={month}
              onChange={onChangeMonth}
              onCurrent={onGoToCurrentMonth}
            />
            <div className="calendar-actions">
              <button
                className={`secondary-small ${batchMode ? "exit-multi" : ""}`}
                onClick={onToggleBatchMode}
              >
                {batchMode ? "退出多选" : "批量修改"}
              </button>
              <button className="primary-small" onClick={onGenerate}>
                <Icon name="spark" /> 循环排班
              </button>
            </div>
          </div>
          {batchMode && (
            <div className="batch-selection-bar">
              <span>
                <strong>
                  {batchDates.length
                    ? `起点：${batchDates[0]}`
                    : "请选择起始日期"}
                </strong>
                <small>
                  {batchDates.length
                    ? "再选截止日，将选择整个区间"
                    : "单日修改不会影响后续循环"}
                </small>
              </span>
            </div>
          )}
          <div className={`calendar-month-stage ${monthMotion}`}>
            <div className="weekday-row">
              {WEEKDAYS.map((day, index) => (
                <span key={day} className={index > 4 ? "weekend" : ""}>
                  周{day}
                </span>
              ))}
            </div>
            <div className="calendar-grid">
              {calendarDays.map((day, index) => {
                if (!day)
                  return (
                    <span className="calendar-spacer" key={`blank-${index}`} />
                  );
                const key = `${year}-${pad(month + 1)}-${pad(day)}`;
                const record = recordMap.get(key);
                const shift = record ? shifts.get(record.shiftId) : undefined;
                const visibleTags =
                  record?.tagIds
                    .map((id) => tags.get(id))
                    .filter((tag): tag is DutyTag => Boolean(tag)) ?? [];
                const holiday = data.display.showHolidays
                  ? statutoryHolidayName(key)
                  : "";
                const selected = batchDateSet.has(key);
                const selectedIndex = batchDates.indexOf(key);
                const completedDay = Boolean(
                  record &&
                    shift?.countsAsWork &&
                    (record.completed || key < todayKey),
                );
                const timeRange = shift ? fullShiftRange(shift) : "";
                const hasVisibleAssignment = Boolean(
                  shift &&
                    (data.display.showShift ||
                      data.display.showTags ||
                      data.display.showShiftTime ||
                      (data.display.showHours &&
                        data.work.trackHours &&
                        shift.countsAsWork &&
                        !shift.isRest)),
                );
                const ariaParts = [
                  `${month + 1}月${day}日`,
                  holiday,
                  shift?.name,
                  ...visibleTags.map((tag) => tag.name),
                ].filter(Boolean);
                return (
                  <button
                    aria-label={ariaParts.join("，")}
                    data-holiday={holiday || undefined}
                    key={key}
                    className={`calendar-day ${key === todayKey ? "today" : ""} ${selected ? "batch-selected" : ""} ${holiday ? "has-holiday" : ""} ${completedDay ? "has-complete" : ""}`}
                    style={shift ? colorStyle(shift.color) : undefined}
                    onClick={() =>
                      batchMode ? onToggleBatchDate(key) : onOpenDate(key)
                    }
                  >
                    <span className="calendar-date-row">
                      <span className="day-number">{day}</span>
                      <span className="calendar-day-badges">
                        {completedDay && (
                          <i className="complete-dot" title="已自动计入" />
                        )}
                      </span>
                    </span>
                    {holiday && (
                      <small className="holiday-flag">
                        法·{statutoryHolidayShortName(holiday)}
                      </small>
                    )}
                    {batchMode && (
                      <span
                        className={`batch-check ${selected ? "" : "pending"}`}
                      >
                        {selectedIndex === 0
                          ? "始"
                          : selectedIndex === batchDates.length - 1 &&
                              batchDates.length > 1
                            ? "止"
                            : selected
                              ? "✓"
                              : ""}
                      </span>
                    )}
                    {shift && hasVisibleAssignment ? (
                      <span className="schedule-cell-content">
                        {data.display.showShiftTime && timeRange && (
                          <small className="schedule-cell-time">
                            {timeRange}
                          </small>
                        )}
                        {data.display.showTags && visibleTags.length > 0 && (
                          <span className="schedule-cell-tags">
                            {visibleTags.slice(0, 2).map((tag) => (
                              <em key={tag.id} style={colorStyle(tag.color)}>
                                {tag.shortName}
                              </em>
                            ))}
                            {visibleTags.length > 2 && (
                              <em>+{visibleTags.length - 2}</em>
                            )}
                          </span>
                        )}
                        <span
                          className={`schedule-cell-shift ${shift.isRest ? "is-rest" : ""}`}
                          style={colorStyle(shift.color)}
                        >
                          {data.display.showShift && <b>{shift.shortName}</b>}
                          {data.display.showHours &&
                            data.work.trackHours &&
                            shift.countsAsWork &&
                            !shift.isRest &&
                            record && (
                              <em>{compactHours(record.hours)}h</em>
                            )}
                        </span>
                      </span>
                    ) : record ? (
                      <span
                        className="calendar-record-dot"
                        style={{ background: shift?.color }}
                      />
                    ) : (
                      <span className="add-day">＋</span>
                    )}
                  </button>
                );
              })}
            </div>
          </div>
          <p className="swipe-hint">‹ 左右滑动切换月份 ›</p>
        </section>
      </div>
      {upcoming && shifts.get(upcoming.shiftId) ? (
        <button
          className="next-shift calendar-next-shift glass-panel"
          onClick={() => onOpenDate(upcoming.date)}
        >
          <span
            className="shift-orb entity-orb"
            style={colorStyle(shifts.get(upcoming.shiftId)!.color)}
          >
            {shifts.get(upcoming.shiftId)!.shortName}
          </span>
          <span>
            <strong>下一班 · {shifts.get(upcoming.shiftId)!.name}</strong>
            <small>
              {upcoming.date}
              {data.work.trackHours
                ? ` · ${compactHours(upcoming.hours)} 小时`
                : ""}
            </small>
          </span>
          <b>›</b>
        </button>
      ) : (
        <div className="empty-schedule-note calendar-next-shift glass-panel">
          <Icon name="calendar" />
          <span>
            <strong>本月暂无后续班次</strong>
            <small>可逐日添加，或使用循环排班。</small>
          </span>
        </div>
      )}
      <section className="month-outlook glass-panel">
        <div className="section-heading">
          <div>
            <p className="eyebrow">本月展望</p>
            <h2>{data.work.trackHours ? "排班与累计工时" : "我的班表"}</h2>
          </div>
          <span className="soft-badge">{workRecords.length} 个工作日</span>
        </div>
        <div className="outlook-metrics dynamic-metrics">
          <MetricCard
            label="计划工作日"
            value={`${workRecords.length}天`}
            detail={`${restDays} 个休息日`}
            tone="blue"
          />
          <MetricCard
            label="已完成班次"
            value={`${completed.length}天`}
            detail={`剩余 ${Math.max(0, workRecords.length - completed.length)} 个班次`}
            tone="green"
          />
          {data.work.trackHours && (
            <MetricCard
              label="本月计划工时"
              value={`${compactHours(projectedHours)}h`}
              detail={`基本工时 ${compactHours(monthlyBasicHours)}h · 已完成 ${compactHours(actualHours)}h`}
              tone="violet"
            />
          )}
          {data.work.trackHours && data.work.trackOvertime && (
            <MetricCard
              label={
                data.work.system === "comprehensive"
                  ? "本周期额外工时"
                  : "本月额外工时"
              }
              value={`${compactHours(overtimeSummary.projected)}h`}
              detail={`${overtimeSummary.label} · 已确认 ${compactHours(overtimeSummary.actual)}h`}
              tone="orange"
            />
          )}
        </div>
      </section>
    </div>
  );
}

function MetricCard({
  label,
  value,
  detail,
  tone,
}: {
  label: string;
  value: string;
  detail: string;
  tone: string;
}) {
  return (
    <article className={`metric-card glass-panel tone-${tone}`}>
      <i className="metric-glow" />
      <p>{label}</p>
      <strong>{value}</strong>
      <small>{detail}</small>
    </article>
  );
}

type ProgressRingTone = "green" | "blue" | "violet" | "yellow" | "gray";
type ProgressRingMetric = {
  id: string;
  label: string;
  completed: number;
  total: number;
  unit: "h" | "天";
  tone: ProgressRingTone;
};
type ShiftBreakdownItem = {
  shift: Shift;
  records: DayRecord[];
  hours: number;
};

function formatRingValue(value: number, unit: ProgressRingMetric["unit"]) {
  return `${compactHours(value)}${unit}`;
}

function ProgressRingDashboard({
  metrics,
  totalLabel,
  totalValue,
  centerLabel,
}: {
  metrics: ProgressRingMetric[];
  totalLabel: string;
  totalValue: string;
  centerLabel: string;
}) {
  const mainMetric = metrics[0];
  const mainPercent = mainMetric?.total
    ? Math.min(100, (mainMetric.completed / mainMetric.total) * 100)
    : 0;

  return (
    <div className="progress-ring-dashboard">
      <div className="progress-rings-stage">
        <svg
          className="progress-rings"
          viewBox="0 0 320 320"
          role="img"
          aria-label={metrics
            .map(
              (metric) =>
                `${metric.label}已完成${formatRingValue(metric.completed, metric.unit)}，剩余${formatRingValue(Math.max(0, metric.total - metric.completed), metric.unit)}`,
            )
            .join("；")}
        >
          {metrics.map((metric, index) => {
            const radius = 132 - index * 29;
            const percent = metric.total
              ? Math.min(100, (metric.completed / metric.total) * 100)
              : 0;
            const angle = (percent / 100) * Math.PI * 2 - Math.PI / 2;
            const endpointX = 160 + Math.cos(angle) * radius;
            const endpointY = 160 + Math.sin(angle) * radius;
            return (
              <g
                key={metric.id}
                className={`progress-ring-group tone-${metric.tone}`}
              >
                <circle
                  className="progress-ring-track"
                  cx="160"
                  cy="160"
                  r={radius}
                  pathLength="100"
                />
                {percent > 0 && (
                  <>
                    <circle
                      className="progress-ring-value"
                      cx="160"
                      cy="160"
                      r={radius}
                      pathLength="100"
                      strokeDasharray={`${percent} ${100 - percent}`}
                    />
                    <circle
                      className="progress-ring-endpoint"
                      cx={endpointX}
                      cy={endpointY}
                      r="6"
                    />
                  </>
                )}
              </g>
            );
          })}
          <text className="progress-ring-center-label" x="160" y="153">
            {centerLabel}
          </text>
          <text className="progress-ring-center-value" x="160" y="181">
            {Math.round(mainPercent)}%
          </text>
        </svg>
      </div>
      <div className="progress-ring-legend">
        <div className="progress-ring-total">
          <i />
          <span>{totalLabel}</span>
          <strong>{totalValue}</strong>
        </div>
        <div className="progress-ring-metrics">
          {metrics.map((metric) => (
            <div
              key={metric.id}
              className="progress-ring-metric"
            >
              <i className={`ring-dot tone-${metric.tone}`} />
              <span>
                <b>{metric.label}</b>
                <small>
                  {metric.total
                    ? `${Math.round((metric.completed / metric.total) * 100)}% 已完成`
                    : "暂无目标"}
                </small>
              </span>
              <strong>{formatRingValue(metric.completed, metric.unit)}</strong>
              <em>/ {formatRingValue(metric.total, metric.unit)}</em>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

function ShiftCompositionBar({
  items,
  showHours = true,
}: {
  items: ShiftBreakdownItem[];
  showHours?: boolean;
}) {
  const totalDays = items.reduce((sum, item) => sum + item.records.length, 0);
  if (!totalDays) return null;
  return (
    <section className="shift-composition-section" aria-label="班次构成">
      <div className="shift-composition-heading">
        <span>
          <small>班次构成</small>
          <strong>全年班次分布</strong>
        </span>
        <b>共 {totalDays} 天</b>
      </div>
      <div className="shift-composition-bar" role="img" aria-label="各班次占比">
        {items.map((item) => {
          const share = (item.records.length / totalDays) * 100;
          return (
            <i
              key={item.shift.id}
              title={`${item.shift.name} ${item.records.length}天，${Math.round(share)}%`}
              style={
                {
                  "--entity-color": item.shift.color,
                  width: `${share}%`,
                } as CSSProperties
              }
            />
          );
        })}
      </div>
      <div className="shift-composition-legend">
        {items.map((item) => {
          const share = (item.records.length / totalDays) * 100;
          return (
            <div key={item.shift.id} style={colorStyle(item.shift.color)}>
              <i />
              <span>
                <strong>{item.shift.name}</strong>
                <small>
                  {item.records.length}天
                  {showHours && item.shift.countsAsWork
                    ? ` · ${compactHours(item.hours)}h`
                    : ""}
                </small>
              </span>
              <b>{Math.round(share)}%</b>
            </div>
          );
        })}
      </div>
    </section>
  );
}

function AnnualRing({
  target,
  actual,
  overtime,
  actualOvertime,
  rest,
  completedRest,
  plannedDays,
  periodLabel,
  composition,
}: {
  target: number;
  actual: number;
  overtime: number;
  actualOvertime: number;
  rest: number;
  completedRest: number;
  plannedDays: number;
  periodLabel: string;
  composition: ShiftBreakdownItem[];
}) {
  const annualTotal = Math.max(0, target + overtime);
  const confirmedOvertime = Math.min(overtime, actualOvertime);
  const confirmedBasic = Math.min(
    target,
    Math.max(0, actual - confirmedOvertime),
  );
  const metrics: ProgressRingMetric[] = [
    {
      id: "total",
      label: `${periodLabel}进度`,
      completed: Math.min(annualTotal, actual),
      total: annualTotal,
      unit: "h",
      tone: "green",
    },
    {
      id: "basic",
      label: "基本工时",
      completed: confirmedBasic,
      total: target,
      unit: "h",
      tone: "blue",
    },
    {
      id: "overtime",
      label: "预测加班",
      completed: confirmedOvertime,
      total: overtime,
      unit: "h",
      tone: "violet",
    },
    {
      id: "rest",
      label: "休息进度",
      completed: Math.min(rest, completedRest),
      total: rest,
      unit: "天",
      tone: "gray",
    },
  ];
  return (
    <div className="annual-progress-content">
      <ProgressRingDashboard
        metrics={metrics}
        totalLabel={`${periodLabel}预计`}
        totalValue={`${compactHours(annualTotal)}h · ${plannedDays}天`}
        centerLabel={`${periodLabel}进度`}
      />
      <ShiftCompositionBar items={composition} />
    </div>
  );
}

function DayCountPie({
  work,
  rest,
  completed,
  completedRest,
  composition,
}: {
  work: number;
  rest: number;
  completed: number;
  completedRest: number;
  composition: ShiftBreakdownItem[];
}) {
  const total = work + rest;
  const elapsed = Math.min(total, completed + completedRest);
  const metrics: ProgressRingMetric[] = [
    {
      id: "elapsed",
      label: "已走过",
      completed: elapsed,
      total,
      unit: "天",
      tone: "green",
    },
    {
      id: "work",
      label: "工作",
      completed: Math.min(work, completed),
      total: work,
      unit: "天",
      tone: "blue",
    },
    {
      id: "rest",
      label: "休息",
      completed: Math.min(rest, completedRest),
      total: rest,
      unit: "天",
      tone: "gray",
    },
  ];
  return (
    <div className="annual-progress-content">
      <ProgressRingDashboard
        metrics={metrics}
        totalLabel="全年预计"
        totalValue={`${total}天`}
        centerLabel="全年进度"
      />
      <ShiftCompositionBar items={composition} showHours={false} />
    </div>
  );
}

function MonthlyHoursChart({
  monthly,
  activeMonth,
  showOvertime,
}: {
  monthly: {
    label: string;
    month: number;
    key: string;
    hours: number;
    completedHours: number;
    target: number;
    overtime: number;
  }[];
  activeMonth: number;
  showOvertime: boolean;
}) {
  return (
    <figure
      className="monthly-bars"
      role="img"
      aria-label="全年每月工作时长柱状图"
    >
      {monthly.map((item, index) => {
        const overtime = showOvertime ? Math.min(item.hours, item.overtime) : 0;
        const base = Math.max(0, item.hours - overtime);
        const baseShare = item.hours > 0 ? (base / item.hours) * 100 : 0;
        const overtimeShare = item.hours > 0 ? 100 - baseShare : 0;
        return (
          <div
            title={`${item.label}：计划 ${compactHours(item.hours)}h，已完成 ${compactHours(item.completedHours)}h${showOvertime ? `，额外 ${compactHours(overtime)}h` : ""}`}
            key={item.key}
            className={`monthly-bar-item ${index === activeMonth ? "is-current" : ""}`}
          >
            <span className="monthly-bar-overtime-value">
              {overtime > 0 ? `+${compactHours(overtime)}h` : ""}
            </span>
            <span className="monthly-bar-total">
              {compactHours(item.hours)}h
            </span>
            <span className="monthly-bar-track">
              {item.hours > 0 && (
                <span className="monthly-bar-fill">
                {overtime > 0 && (
                  <i
                    className="monthly-bar-overtime"
                    style={{ height: `${overtimeShare}%` }}
                  />
                )}
                  <i
                    className="monthly-bar-basic"
                    style={{ height: `${baseShare}%` }}
                  />
                </span>
              )}
            </span>
            <small>{item.month + 1}月</small>
          </div>
        );
      })}
    </figure>
  );
}

function StatsView({
  year,
  month,
  data,
  todayKey,
  onChangeMonth,
  onGoToCurrentMonth,
}: {
  year: number;
  month: number;
  data: AppData;
  todayKey: string;
  onChangeMonth: (delta: number) => void;
  onGoToCurrentMonth: () => void;
}) {
  const [ringScope, setRingScope] = useState<StatsScope>("year");
  const shiftMap = useMemo(
    () => new Map(data.shifts.map((shift) => [shift.id, shift])),
    [data.shifts],
  );
  const annualCycle = reportingCycleForMonth(data, year, month);
  const annualRecords = recordsForMonths(data.records, annualCycle.months);
  const workRecords = annualRecords.filter(
    (record) => shiftMap.get(record.shiftId)?.countsAsWork,
  );
  const restRecords = annualRecords.filter(
    (record) => shiftMap.get(record.shiftId)?.isRest,
  );
  const completed = completedByDate(workRecords, todayKey);
  const completedRest = completedByDate(restRecords, todayKey);
  const actualHours = completed.reduce((sum, record) => sum + record.hours, 0);
  const annualTarget = getAnnualTarget(data, annualCycle.months);
  const annualOvertime = getPeriodOvertime(
    workRecords,
    data,
    annualCycle.months,
  );
  const actualOvertime = getPeriodOvertime(
    completed,
    data,
    annualCycle.months,
  );
  const monthPrefix = `${year}-${pad(month + 1)}`;
  const monthWorkRecords = workRecords.filter((record) =>
    record.date.startsWith(monthPrefix),
  );
  const monthRestRecords = restRecords.filter((record) =>
    record.date.startsWith(monthPrefix),
  );
  const completedMonthWork = completedByDate(monthWorkRecords, todayKey);
  const completedMonthRest = completedByDate(monthRestRecords, todayKey);
  const monthTarget = getMonthlyTarget(data, year, month);
  const monthActualHours = completedMonthWork.reduce(
    (sum, record) => sum + record.hours,
    0,
  );
  const monthOvertime = calculateOvertime(
    monthWorkRecords,
    data.work,
    monthTarget,
  );
  const actualMonthOvertime = calculateOvertime(
    completedMonthWork,
    data.work,
    monthTarget,
  );
  const ringTarget = ringScope === "year" ? annualTarget : monthTarget;
  const ringActualHours = ringScope === "year" ? actualHours : monthActualHours;
  const ringOvertime = ringScope === "year" ? annualOvertime : monthOvertime;
  const ringActualOvertime =
    ringScope === "year" ? actualOvertime : actualMonthOvertime;
  const ringRestRecords = ringScope === "year" ? restRecords : monthRestRecords;
  const ringCompletedRest =
    ringScope === "year" ? completedRest : completedMonthRest;
  const ringWorkRecords = ringScope === "year" ? workRecords : monthWorkRecords;
  const ringRecords =
    ringScope === "year"
      ? annualRecords
      : annualRecords.filter((record) => record.date.startsWith(monthPrefix));
  const ringPeriodLabel = ringScope === "year" ? "年度" : `${month + 1}月`;
  const monthlyOvertime = canAllocateOvertimeByMonth(data);
  const shiftBreakdown = data.shifts
    .map((shift) => {
      const records = ringRecords.filter((record) => record.shiftId === shift.id);
      return {
        shift,
        records,
        hours: records.reduce((sum, record) => sum + record.hours, 0),
      };
    })
    .filter((item) => item.records.length)
    .sort((a, b) => b.records.length - a.records.length);
  const annualShiftBreakdown = data.shifts
    .map((shift) => {
      const records = annualRecords.filter(
        (record) => record.shiftId === shift.id,
      );
      return {
        shift,
        records,
        hours: records.reduce((sum, record) => sum + record.hours, 0),
      };
    })
    .filter((item) => item.records.length)
    .sort((a, b) => b.records.length - a.records.length);
  const activeMonthIndex = annualCycle.months.findIndex(
    (item) => item.year === year && item.month === month,
  );
  const monthly = annualCycle.months.map((item) => {
    const records = workRecords.filter((record) =>
      record.date.startsWith(item.key),
    );
    const completedRecords = completedByDate(records, todayKey);
    const target = getMonthlyTarget(data, item.year, item.month);
    const overtime = !data.work.trackOvertime
      ? 0
      : data.work.system === "comprehensive"
        ? data.work.period === "month"
          ? calculateOvertime(records, data.work, target)
          : data.work.period === "week"
            ? comprehensiveScopeForMonth(
                data,
                item.year,
                item.month,
                workRecords,
                todayKey,
              ).projected
            : 0
        : calculateOvertime(records, data.work, target);
    return {
      label: MONTH_LABELS[item.month],
      month: item.month,
      key: item.key,
      hours: records.reduce((sum, record) => sum + record.hours, 0),
      completedHours: completedRecords.reduce(
        (sum, record) => sum + record.hours,
        0,
      ),
      target,
      overtime,
    };
  });
  const systemNote =
    data.work.system === "comprehensive"
      ? `${annualCycle.label}为当前年度工时范围；综合工时按${PERIOD_LABELS[data.work.period]}周期累计，月度基本工时按每日 8h 推算。`
      : data.work.system === "standard"
        ? "标准工时按已开启的每日 / 每周阈值统计，日与周结果取较高值，避免重复累计。"
        : data.work.system === "custom"
          ? "额外工时按你的自定义阈值或手动标记统计。"
          : "额外工时只读取每天手动填写的数值，不自动套用每日 8 小时规则。";

  if (!data.work.trackHours)
    return (
      <div className="stats-page">
        <section className="glass-panel schedule-only-overview">
          <div className="schedule-only-copy">
            <MonthSwitch
              year={year}
              month={month}
              onChange={onChangeMonth}
              onCurrent={onGoToCurrentMonth}
              compact
            />
            <PeriodRange
              cycle={annualCycle}
              year={year}
              month={month}
              annual
            />
            <p className="eyebrow">仅排班模式</p>
            <h2>这一周期安排了 {workRecords.length} 个工作日</h2>
            <p>
              工时统计已关闭，因此这里只展示班次与天数，不推算工时或额外工时。
            </p>
          </div>
          <DayCountPie
            work={workRecords.length}
            rest={restRecords.length}
            completed={completed.length}
            completedRest={completedRest.length}
            composition={annualShiftBreakdown}
          />
        </section>
        <div className="stats-summary-grid schedule-summary">
          <MetricCard
            label="计划工作日"
            value={`${workRecords.length}天`}
            detail="计入工作的班次"
            tone="blue"
          />
          <MetricCard
            label="已完成班次"
            value={`${completed.length}天`}
            detail={`剩余 ${Math.max(0, workRecords.length - completed.length)} 天`}
            tone="green"
          />
          <MetricCard
            label="休息日"
            value={`${restRecords.length}天`}
            detail="休息与请假班次"
            tone="gray"
          />
        </div>
      </div>
    );

  return (
    <div className="stats-page">
      <div className="stats-layout annual-dashboard">
        {data.work.trackOvertime && data.work.system === "comprehensive" && (
          <section className="annual-overview-card glass-panel">
            <div className="section-heading">
              <div>
                <p className="eyebrow">
                  {ringScope === "year" ? "年度" : "月度"}工时仪表盘
                </p>
                <h2>标准、额外与完成进度</h2>
                <PeriodRange
                  cycle={annualCycle}
                  year={year}
                  month={month}
                  annual={ringScope === "year"}
                />
              </div>
              <div className="stats-heading-controls">
                <MonthSwitch
                  year={year}
                  month={month}
                  onChange={onChangeMonth}
                  onCurrent={onGoToCurrentMonth}
                  compact
                />
                <div className="stats-period-toggle" aria-label="统计周期">
                  <button
                    type="button"
                    className={ringScope === "month" ? "active" : ""}
                    aria-pressed={ringScope === "month"}
                    onClick={() => setRingScope("month")}
                  >
                    月
                  </button>
                  <button
                    type="button"
                    className={ringScope === "year" ? "active" : ""}
                    aria-pressed={ringScope === "year"}
                    onClick={() => setRingScope("year")}
                  >
                    年
                  </button>
                </div>
              </div>
            </div>
            <div className="annual-overview-grid">
              <AnnualRing
                key={`${ringScope}-${year}-${month}`}
                target={ringTarget}
                actual={ringActualHours}
                overtime={ringOvertime}
                actualOvertime={ringActualOvertime}
                rest={ringRestRecords.length}
                completedRest={ringCompletedRest.length}
                plannedDays={ringWorkRecords.length + ringRestRecords.length}
                periodLabel={ringPeriodLabel}
                composition={shiftBreakdown}
              />
            </div>
          </section>
        )}
        <section className="glass-panel stats-rule-note">
          <Icon name="spark" />
          <div>
            <strong>
              {data.work.trackOvertime
                ? SYSTEM_LABELS[data.work.system]
                : "仅统计工作时长"}
            </strong>
            <p>
              {data.work.trackOvertime
                ? systemNote
                : "加班统计已关闭。图表只展示计划工时、已完成工时和班次构成。"}
            </p>
          </div>
          {data.work.system !== "comprehensive" && (
            <MonthSwitch
              year={year}
              month={month}
              onChange={onChangeMonth}
              onCurrent={onGoToCurrentMonth}
              compact
            />
          )}
        </section>
        <section className="chart-card glass-panel">
          <div className="section-heading">
            <div>
              <p className="eyebrow">12 个月</p>
              <h2>
                {data.work.trackOvertime && monthlyOvertime
                  ? "每月工时与额外工时"
                  : "每月计划与完成工时"}
              </h2>
            </div>
            <div className="chart-legend">
              <span>
                <i className="bar-blue" />
                标准内 / 工作时长
              </span>
              {data.work.trackOvertime && monthlyOvertime && (
                <span>
                  <i className="bar-overtime-key" />
                  额外工时
                </span>
              )}
            </div>
          </div>
          {!monthlyOvertime &&
            data.work.trackOvertime &&
            data.work.system === "comprehensive" && (
              <p className="chart-caption">
                当前按{PERIOD_LABELS[data.work.period]}
                统一结算，月柱不拆分额外工时，以免把周期口径误解为“每月超过即加班”。
              </p>
            )}
          <MonthlyHoursChart
            monthly={monthly}
            activeMonth={activeMonthIndex}
            showOvertime={monthlyOvertime}
          />
        </section>
      </div>
    </div>
  );
}

function CalendarDisplayPreview({ data }: { data: AppData }) {
  const shift = data.shifts.find((item) => item.countsAsWork) ?? data.shifts[0];
  const previewTags = data.tags.slice(0, 2);
  const timeRange = shift ? fullShiftRange(shift) : "";
  return (
    <div className="calendar-display-preview">
      <div
        className="calendar-day preview-calendar-cell"
        style={shift ? colorStyle(shift.color) : undefined}
      >
        <span className="calendar-date-row">
          <span className="day-number">8</span>
          <span className="calendar-day-badges">
            <i className="complete-dot" title="已自动计入" />
          </span>
        </span>
        {data.display.showHolidays && (
          <small className="holiday-flag">法·国庆</small>
        )}
        {shift && (
          <span className="schedule-cell-content">
            {data.display.showShiftTime && timeRange && (
              <small className="schedule-cell-time">{timeRange}</small>
            )}
            {data.display.showTags && previewTags.length > 0 && (
              <span className="schedule-cell-tags">
                {previewTags.map((tag) => (
                  <em key={tag.id} style={colorStyle(tag.color)}>
                    {tag.shortName}
                  </em>
                ))}
              </span>
            )}
            <span
              className={`schedule-cell-shift ${shift.isRest ? "is-rest" : ""}`}
              style={colorStyle(shift.color)}
            >
              {data.display.showShift && <b>{shift.shortName}</b>}
              {data.display.showHours &&
                data.work.trackHours &&
                shift.countsAsWork &&
                !shift.isRest && <em>{compactHours(shift.defaultHours)}h</em>}
            </span>
          </span>
        )}
      </div>
      <span className="calendar-preview-guidance">
        <span className="calendar-preview-copy">
          <strong>单元格效果预览</strong>
          <small>左侧预览会随上方显示选项实时同步</small>
        </span>
        <small>
          绿点表示班次已完成；法定节假日显示在日期右侧。实际日历会根据屏幕宽度自动压缩文字。
        </small>
      </span>
    </div>
  );
}

function SettingsView({
  data,
  setData,
  activeYear,
  activeMonth,
  onOpenGenerator,
  notify,
}: {
  data: AppData;
  setData: (value: AppData | ((current: AppData) => AppData)) => void;
  activeYear: number;
  activeMonth: number;
  onOpenGenerator: () => void;
  notify: (message?: string) => void;
}) {
  const [editor, setEditor] = useState<EntityEditor>(null);
  const [message, setMessage] = useState("");
  const currentCycle = reportingCycleForMonth(
    data,
    activeYear,
    activeMonth,
  );
  const currentCycleStartYear = currentCycle.startYear;
  const [targetYear, setTargetYear] = useState(currentCycleStartYear);
  const [targetEdit, setTargetEdit] = useState<{
    key: string;
    value: number;
  } | null>(null);
  const importInput = useRef<HTMLInputElement>(null);
  const orderedShiftItems = orderedShifts(data.shifts);
  const selectedCareer =
    CAREERS.find((career) => career.id === data.careerPreset) ?? CAREERS[0];
  const targetCycle = getAnnualCycle(
    targetYear,
    data.work.annualStartMonth - 1,
    data.work.annualStartMonth,
  );
  function updateWork(patch: Partial<AppData["work"]>) {
    const linkedValue = patch.trackHours ?? patch.trackOvertime;
    setData((current) => {
      const nextSystem = patch.system ?? current.work.system;
      const next = {
        ...current,
        work: {
          ...current.work,
          ...patch,
          period:
            nextSystem === "comprehensive"
              ? "month"
              : (patch.period ?? current.work.period),
          ...(typeof linkedValue === "boolean"
            ? { trackHours: linkedValue, trackOvertime: linkedValue }
            : {}),
        },
      };
      return materializeReportingYears(next, activeYear, activeMonth);
    });
  }
  function updateDisplay(patch: Partial<AppData["display"]>) {
    setData((current) => ({
      ...current,
      display: { ...current.display, ...patch },
    }));
  }
  function saveShift(shift: Shift) {
    const normalizedShift =
      shift.id === "shift-rest"
        ? { ...shift, color: ACCENT_COLORS.gray }
        : shift;
    if (
      data.shifts.some(
        (item) =>
          item.id !== normalizedShift.id &&
          item.name.trim() === normalizedShift.name.trim() &&
          item.startTime === normalizedShift.startTime &&
          item.endTime === normalizedShift.endTime,
      )
    ) {
      setMessage("已有名称和时间相同的班次，请直接编辑现有班次。");
      return;
    }
    setData((current) => ({
      ...current,
      shifts: [
        ...current.shifts.filter((item) => item.id !== normalizedShift.id),
        normalizedShift,
      ],
    }));
    setEditor(null);
    notify();
  }
  function deleteShift(shift: Shift) {
    const usedByRecord = data.records.some(
      (record) => record.shiftId === shift.id,
    );
    const usedByCycle = data.activeCycle?.shiftIds.includes(shift.id);
    if (usedByRecord || usedByCycle) {
      setMessage(
        `“${shift.name}”正在被每日排班或当前循环使用，请先替换后再删除。`,
      );
      return;
    }
    setData((current) => ({
      ...current,
      shifts: current.shifts.filter((item) => item.id !== shift.id),
      cycleTemplates: current.cycleTemplates.filter(
        (template) => !template.shiftIds.includes(shift.id),
      ),
    }));
    notify("班次与相关模板已删除");
  }
  function saveTag(tag: DutyTag) {
    if (
      data.tags.some(
        (item) => item.id !== tag.id && item.name.trim() === tag.name.trim(),
      )
    ) {
      setMessage("已有同名标签，请直接编辑现有标签。");
      return;
    }
    setData((current) => ({
      ...current,
      tags: [...current.tags.filter((item) => item.id !== tag.id), tag],
    }));
    setEditor(null);
    notify();
  }
  function deleteTag(tag: DutyTag) {
    setData((current) => ({
      ...current,
      tags: current.tags.filter((item) => item.id !== tag.id),
      records: current.records.map((record) => ({
        ...record,
        tagIds: record.tagIds.filter((id) => id !== tag.id),
      })),
    }));
    notify("标签已删除");
  }
  function exportBackup() {
    const blob = new Blob(
      [
        JSON.stringify(
          {
            app: "calenease",
            version: DATA_VERSION,
            exportedAt: new Date().toISOString(),
            data,
          },
          null,
          2,
        ),
      ],
      { type: "application/json" },
    );
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = `省心日历备份-${dateKey(new Date())}.json`;
    anchor.click();
    URL.revokeObjectURL(url);
  }
  async function importBackup(file?: File) {
    if (!file) return;
    try {
      const parsed = JSON.parse(await file.text()) as Record<string, unknown>;
      const next = parsed.data
        ? normalizeAppData(parsed.data)
        : parsed.settings || parsed.records
          ? migrateLegacyData(parsed.settings, parsed.records)
          : normalizeAppData(parsed);
      setData(next);
      setMessage(`已导入 ${next.records.length} 天记录`);
    } catch {
      setMessage("导入失败：请选择省心日历（或旧版循环班表）导出的 JSON 备份");
    } finally {
      if (importInput.current) importInput.current.value = "";
    }
  }
  return (
    <>
      <div className="settings-grid upgraded-settings">
        <section className="glass-panel setting-card wide career-preset-card">
          <div className="section-heading">
            <div>
              <p className="eyebrow">工作类型 / 职业预设</p>
              <h2>选择你的工作类型</h2>
            </div>
          </div>
          <label className="career-unified-picker">
            <select
              aria-label="选择工作类型"
              value={data.careerPreset}
              onChange={(event) => {
                const preset = event.target.value as CareerPreset;
                setData((current) => applyCareerPreset(current, preset));
                notify(
                  `已切换为${CAREERS.find((item) => item.id === preset)?.name ?? "自定义"}预设`,
                );
              }}
            >
              {CAREERS.map((career) => (
                <option value={career.id} key={career.id}>
                  {career.name}
                </option>
              ))}
            </select>
            <span className="career-picker-head">
              <span>
                <small>当前工作类型</small>
                <strong>{selectedCareer.name}</strong>
              </span>
              <SelectChevron />
            </span>
            <span className="career-picker-detail">{selectedCareer.detail}</span>
            <small className="career-picker-note">
              点按整张卡片即可更换。只补充相关的起始班次、示例标签和推荐模板，不会限制自定义功能，也不会删除已有内容。
            </small>
            <span className="career-feature-chips">
              {CAREER_FEATURES[data.careerPreset].map((feature) => (
                <i key={feature}>{feature}</i>
              ))}
            </span>
          </label>
        </section>
        <section className="glass-panel setting-card wide calendar-display-card">
          <div className="section-heading">
            <div>
              <p className="eyebrow">日历显示</p>
              <h2>选择单元格中显示的信息</h2>
            </div>
          </div>
          <div className="calendar-display-layout">
            <div className="calendar-display-options">
              <ToggleRow
                label="班次简称"
                detail="例如：白、夜、大夜"
                checked={data.display.showShift}
                onChange={(checked) => updateDisplay({ showShift: checked })}
              />
              <ToggleRow
                label="职责标签"
                detail="显示当天附加的责班、ICU 等标签"
                checked={data.display.showTags}
                onChange={(checked) => updateDisplay({ showTags: checked })}
              />
              <ToggleRow
                label="班次时间"
                detail="例如：08:00–20:00"
                checked={data.display.showShiftTime}
                onChange={(checked) =>
                  updateDisplay({ showShiftTime: checked })
                }
              />
              {data.work.trackHours && (
                <ToggleRow
                  label="计入工时"
                  detail="显示当天实际 / 计划计入的小时数"
                  checked={data.display.showHours}
                  onChange={(checked) => updateDisplay({ showHours: checked })}
                />
              )}
              <ToggleRow
                label="法定节假日"
                detail="显示元旦、春节、清明、劳动节等标签"
                checked={data.display.showHolidays}
                onChange={(checked) => updateDisplay({ showHolidays: checked })}
              />
            </div>
            <CalendarDisplayPreview data={data} />
          </div>
        </section>
        <section className="glass-panel setting-card wide">
          <div className="section-heading">
            <div>
              <p className="eyebrow">排班设置</p>
              <h2>我的班次</h2>
            </div>
            <button
              className="primary-small"
              onClick={() => setEditor({ type: "shift" })}
            >
              <Icon name="plus" /> 创建班次
            </button>
          </div>
          <p className="setting-intro">
            班次只描述工作时间。名称、简称、颜色、跨天和默认工时都可以修改。
          </p>
          <div className="shift-card-grid">
            {orderedShiftItems.map((shift) => (
              <article
                key={shift.id}
                className="shift-library-item"
                style={colorStyle(shift.color)}
              >
                <div className="shift-library-top">
                  <i>{shift.shortName}</i>
                  <span>
                    <button
                      aria-label={`编辑${shift.name}`}
                      onClick={() => setEditor({ type: "shift", value: shift })}
                    >
                      <Icon name="edit" />
                    </button>
                    <button
                      aria-label={`删除${shift.name}`}
                      className="mini-delete"
                      onClick={() => deleteShift(shift)}
                    >
                      <Icon name="trash" />
                    </button>
                  </span>
                </div>
                <strong>{shift.name}</strong>
                <small>
                  {shift.isRest
                    ? "休息 / 不计工时"
                    : `${compactShiftRange(shift) || "未设置时间"} · ${shift.countsAsWork ? `${compactHours(shift.defaultHours)}h` : "不计"}`}
                </small>
              </article>
            ))}
          </div>
        </section>
        <section className="glass-panel setting-card wide">
          <div className="section-heading">
            <div>
              <p className="eyebrow">职责信息层</p>
              <h2>我的标签</h2>
            </div>
            <button
              className="primary-small"
              onClick={() => setEditor({ type: "tag" })}
            >
              <Icon name="tag" /> 创建标签
            </button>
          </div>
          <p className="setting-intro">
            标签可叠加在每天的主班次上，不参与循环工时计算。
          </p>
          <div className="tag-card-grid">
            {data.tags.length ? (
              data.tags.map((tag) => (
                <article
                  key={tag.id}
                  className="tag-library-item"
                  style={colorStyle(tag.color)}
                >
                  <div className="tag-library-top">
                    <i>{tag.shortName}</i>
                    <span>
                      <button
                        aria-label={`编辑${tag.name}`}
                        onClick={() => setEditor({ type: "tag", value: tag })}
                      >
                        <Icon name="edit" />
                      </button>
                      <button
                        aria-label={`删除${tag.name}`}
                        className="mini-delete"
                        onClick={() => deleteTag(tag)}
                      >
                        <Icon name="trash" />
                      </button>
                    </span>
                  </div>
                  <strong>{tag.name}</strong>
                  <small>日历简称 · {tag.shortName}</small>
                </article>
              ))
            ) : (
              <p className="empty-copy">
                还没有标签。护士可添加“责班、主班、门诊、ICU”等职责。
              </p>
            )}
          </div>
        </section>
        <section className="glass-panel setting-card wide current-cycle-card">
          <div className="section-heading">
            <div>
              <p className="eyebrow">循环排班</p>
              <h2>{data.activeCycle?.name ?? "尚未启用循环"}</h2>
            </div>
            <button className="primary-small" onClick={onOpenGenerator}>
              <Icon name="spark" /> {data.activeCycle ? "修改循环" : "创建循环"}
            </button>
          </div>
          {data.activeCycle ? (
            <>
              <p className="setting-intro">
                从 {data.activeCycle.startDate} 起按班次 ID
                序列无限重复；单日修改不会改变后续节奏。
              </p>
              <div className="cycle-preview-line">
                {data.activeCycle.shiftIds.map((id, index) => {
                  const shift = data.shifts.find((item) => item.id === id);
                  return (
                    shift && (
                      <span
                        key={`${id}-${index}`}
                        style={colorStyle(shift.color)}
                      >
                        {shift.shortName}
                      </span>
                    )
                  );
                })}
              </div>
            </>
          ) : (
            <p className="setting-intro">
              普通用户可直接选模板，高级用户可按任意班次顺序创建自己的循环。
            </p>
          )}
        </section>
        <section className="glass-panel setting-card wide work-settings-card">
          <div className="section-heading">
            <div>
              <p className="eyebrow">工时与加班</p>
              <h2>按需开启统计模块</h2>
            </div>
          </div>
          <ToggleRow
            label="统计工时与加班"
            detail="关闭后仍可正常排班；开启后同时统计工作时长与加班"
            checked={data.work.trackHours}
            onChange={(checked) => updateWork({ trackHours: checked })}
          />
          {data.work.trackHours && (
            <div className="conditional-settings">
                  <SelectSetting
                    label="工时制度"
                    value={data.work.system}
                    onChange={(value) =>
                      updateWork({ system: value as WorkSystem })
                    }
                    options={Object.entries(SYSTEM_LABELS)}
                  />
                  {data.work.system === "comprehensive" && (
                    <div className="annual-cycle-setting">
                      <SelectSetting
                        label="年度工时起止月份"
                        value={String(data.work.annualStartMonth)}
                        onChange={(value) => {
                          const annualStartMonth = Number(value);
                          setTargetYear(
                            getAnnualCycle(
                              activeYear,
                              activeMonth,
                              annualStartMonth,
                            ).startYear,
                          );
                          updateWork({ annualStartMonth });
                        }}
                        options={Array.from({ length: 12 }, (_, index) => {
                          const start = index + 1;
                          const end = start === 1 ? 12 : start - 1;
                          return [
                            String(start),
                            start === 1
                              ? "1月—12月"
                              : `${start}月—次年${end}月`,
                          ];
                        })}
                      />
                      <p className="annual-cycle-note">
                        当前年度范围：
                        <strong>{currentCycle.label}</strong>
                        。年度统计、额外工时和月度图表会同步按这个范围计算。
                      </p>
                    </div>
                  )}
                  {data.work.system === "standard" && (
                    <>
                      <NumberSetting
                        label="每日标准工时"
                        value={data.work.dailyStandard}
                        unit="h"
                        onChange={(value) =>
                          updateWork({ dailyStandard: value })
                        }
                      />
                      <ToggleRow
                        label="启用每日标准"
                        detail="例如 10h − 8h = 2h"
                        checked={data.work.standardDailyEnabled}
                        onChange={(checked) =>
                          updateWork({ standardDailyEnabled: checked })
                        }
                      />
                      <NumberSetting
                        label="每周标准工时"
                        value={data.work.weeklyStandard}
                        unit="h"
                        onChange={(value) =>
                          updateWork({ weeklyStandard: value })
                        }
                      />
                      <ToggleRow
                        label="启用每周标准"
                        detail="日与周结果取较高值，避免重复累计"
                        checked={data.work.standardWeeklyEnabled}
                        onChange={(checked) =>
                          updateWork({ standardWeeklyEnabled: checked })
                        }
                      />
                    </>
                  )}
                  {data.work.system === "custom" && (
                    <>
                      <SelectSetting
                        label="自定义规则"
                        value={data.work.customRule}
                        onChange={(value) =>
                          updateWork({
                            customRule: value as AppData["work"]["customRule"],
                          })
                        }
                        options={[
                          ["daily", "每天超过 X 小时"],
                          ["weekly", "每周超过 X 小时"],
                          ["monthly", "每月超过 X 小时"],
                          ["period", "周期超过 X 小时"],
                          ["manual", "完全手动标记"],
                        ]}
                      />
                      {data.work.customRule !== "manual" && (
                        <NumberSetting
                          label="阈值 X"
                          value={data.work.customThreshold}
                          unit="h"
                          onChange={(value) =>
                            updateWork({ customThreshold: value })
                          }
                        />
                      )}
                    </>
                  )}
                  {(data.work.system === "irregular" ||
                    data.work.system === "manual") && (
                    <p className="conditional-note">
                      此模式不会自动套用每日 8
                      小时规则。需要额外工时时，请在当天详情中手动填写。
                    </p>
                  )}
                  <SelectSetting
                    label="加班如何记录 / 补偿"
                    value={data.work.compensation}
                    onChange={(value) =>
                      updateWork({
                        compensation: value as AppData["work"]["compensation"],
                      })
                    }
                    options={[
                      ["hours", "只记录小时"],
                      ["salary", "加班工资"],
                      ["timeOff", "调休"],
                      ["fixed", "固定金额"],
                      ["custom", "自定义"],
                      ["none", "暂不统计收入"],
                    ]}
                  />
            </div>
          )}
        </section>
        {data.work.trackHours &&
          data.work.trackOvertime &&
          data.work.system === "comprehensive" && (
            <section className="glass-panel setting-card wide target-explorer">
              <div className="section-heading">
                <div>
                  <p className="eyebrow">综合工时标准</p>
                  <h2>月度标准工时</h2>
                  <PeriodRange
                    cycle={targetCycle}
                    year={targetYear}
                    month={targetCycle.startMonth}
                    annual
                  />
                </div>
                <div className="target-year-switch">
                  <button
                    aria-label="上一年"
                    onClick={() => setTargetYear((value) => value - 1)}
                  >
                    ‹
                  </button>
                  <strong>{targetYear}年</strong>
                  <button
                    aria-label="下一年"
                    onClick={() => setTargetYear((value) => value + 1)}
                  >
                    ›
                  </button>
                </div>
              </div>
              <p className="target-grid-note">
                系统按工作日统一自动推演；点按任意月份可手动修正。
              </p>
              <div className="target-grid">
                {targetCycle.months.map((item) => {
                  const label = MONTH_LABELS[item.month];
                  const key = item.key;
                  const value = getMonthlyTarget(data, item.year, item.month);
                  const overridden = Number.isFinite(data.targets[key]);
                  return (
                    <button
                      className={overridden ? "overridden" : ""}
                      key={key}
                      aria-label={`${label} ${compactHours(value)} 小时，点按修改`}
                      onClick={() => setTargetEdit({ key, value })}
                    >
                      <span className="target-month-copy">
                        <b>{label}</b>
                        {overridden && <small>已修正</small>}
                      </span>
                      <strong>
                        {compactHours(value)}
                        <b>h</b>
                      </strong>
                    </button>
                  );
                })}
              </div>
            </section>
          )}
        <section className="glass-panel setting-card wide data-card">
          <div>
            <p className="eyebrow">数据</p>
            <h2>备份与恢复</h2>
            <span>备份包含自定义班次、标签、循环、工时规则和每日记录。</span>
            {message && (
              <strong
                className={`import-message ${message.includes("失败") || message.includes("正在被") ? "error" : ""}`}
              >
                {message}
              </strong>
            )}
          </div>
          <div className="data-actions">
            <button className="secondary-button" onClick={exportBackup}>
              <Icon name="download" />
              导出备份
            </button>
            <button
              className="secondary-button"
              onClick={() => importInput.current?.click()}
            >
              <Icon name="upload" />
              导入备份
            </button>
            <input
              ref={importInput}
              className="file-input"
              type="file"
              accept="application/json,.json"
              onChange={(event: ChangeEvent<HTMLInputElement>) =>
                importBackup(event.target.files?.[0])
              }
            />
          </div>
        </section>
        <section className="glass-panel setting-card wide about-card">
          <div>
            <p className="eyebrow">关于</p>
            <h2>省心日历 {APP_VERSION}</h2>
            <span>
              数据只保存在本机，不上传服务器。工时为个人预估，最终以公司考勤记录
              和适用制度为准。
            </span>
          </div>
          <div className="data-actions">
            <a
              className="secondary-button"
              href={PRIVACY_URL}
              target="_blank"
              rel="noreferrer"
            >
              隐私政策
            </a>
            <a
              className="secondary-button"
              href={SUPPORT_URL}
              target="_blank"
              rel="noreferrer"
            >
              反馈与支持
            </a>
          </div>
        </section>
      </div>
      {editor?.type === "shift" && (
        <ShiftEditor
          value={editor.value}
          onClose={() => setEditor(null)}
          onSave={saveShift}
        />
      )}{" "}
      {editor?.type === "tag" && (
        <TagEditor
          value={editor.value}
          onClose={() => setEditor(null)}
          onSave={saveTag}
        />
      )}{" "}
      {targetEdit && (
        <NumberModal
          title="修改月度标准工时"
          value={targetEdit.value}
          unit="小时"
          onClose={() => setTargetEdit(null)}
          onSave={(value) => {
            setData((current) => ({
              ...current,
              targets: { ...current.targets, [targetEdit.key]: value },
            }));
            setTargetEdit(null);
            notify();
          }}
        />
      )}
    </>
  );
}

function ToggleRow({
  label,
  detail,
  checked,
  onChange,
}: {
  label: string;
  detail: string;
  checked: boolean;
  onChange: (checked: boolean) => void;
}) {
  return (
    <label className="setting-toggle">
      <span>
        <strong>{label}</strong>
        <small>{detail}</small>
      </span>
      <input
        type="checkbox"
        checked={checked}
        onChange={(event) => onChange(event.target.checked)}
      />
      <i />
    </label>
  );
}
function SelectSetting({
  label,
  value,
  options,
  onChange,
}: {
  label: string;
  value: string;
  options: string[][];
  onChange: (value: string) => void;
}) {
  return (
    <label className="select-setting">
      <span>{label}</span>
      <span className="select-control">
        <select
          value={value}
          onChange={(event) => onChange(event.target.value)}
        >
          {options.map(([id, name]) => (
            <option key={id} value={id}>
              {name}
            </option>
          ))}
        </select>
        <SelectChevron />
      </span>
    </label>
  );
}

function SelectChevron() {
  return (
    <span className="select-chevron" aria-hidden="true">
      <svg viewBox="0 0 16 16">
        <path d="M3.5 6.25 8 10.5l4.5-4.25" />
      </svg>
    </span>
  );
}
function NumberSetting({
  label,
  value,
  unit,
  onChange,
}: {
  label: string;
  value: number;
  unit: string;
  onChange: (value: number) => void;
}) {
  return (
    <label className="number-setting">
      <span>{label}</span>
      <div>
        <input
          type="number"
          min="0"
          step="0.5"
          value={value}
          onChange={(event) =>
            onChange(Math.max(0, Number(event.target.value) || 0))
          }
        />
        <b>{unit}</b>
      </div>
    </label>
  );
}

function ShiftEditor({
  value,
  onClose,
  onSave,
}: {
  value?: Shift;
  onClose: () => void;
  onSave: (shift: Shift) => void;
}) {
  const [draft, setDraft] = useState<Shift>(
    value ?? {
      id: makeId("shift"),
      name: "新班次",
      shortName: "新",
      color: SHIFT_COLORS[0],
      startTime: "08:00",
      endTime: "16:00",
      crossesMidnight: false,
      isRest: false,
      defaultHours: 8,
      countsAsWork: true,
    },
  );
  function updateTime(patch: Partial<Shift>) {
    setDraft((current) => {
      const next = { ...current, ...patch };
      return {
        ...next,
        defaultHours: next.isRest
          ? 0
          : calculateShiftDuration(
              next.startTime,
              next.endTime,
              next.crossesMidnight,
            ),
      };
    });
  }
  return (
    <div className="modal-backdrop" onMouseDown={onClose}>
      <section
        className="dialog-card glass-panel entity-editor"
        onMouseDown={(event) => event.stopPropagation()}
      >
        <div className="sheet-header">
          <div>
            <p className="eyebrow">自定义班次</p>
            <h2>{value ? "编辑班次" : "创建班次"}</h2>
          </div>
          <button
            aria-label="关闭弹窗"
            className="close-button"
            onClick={onClose}
          >
            ×
          </button>
        </div>
        <div className="form-grid">
          <label>
            <span>班次名称</span>
            <input
              value={draft.name}
              onChange={(event) =>
                setDraft({ ...draft, name: event.target.value })
              }
            />
          </label>
          <label>
            <span>简称</span>
            <input
              maxLength={4}
              value={draft.shortName}
              onChange={(event) =>
                setDraft({ ...draft, shortName: event.target.value })
              }
            />
          </label>
          <label>
            <span>开始时间</span>
            <input
              type="time"
              disabled={draft.isRest}
              value={draft.startTime}
              onChange={(event) =>
                updateTime({ startTime: event.target.value })
              }
            />
          </label>
          <label>
            <span>结束时间</span>
            <input
              type="time"
              disabled={draft.isRest}
              value={draft.endTime}
              onChange={(event) => updateTime({ endTime: event.target.value })}
            />
          </label>
        </div>
        <ToggleRow
          label="跨午夜"
          detail="例如 20:00–08:00"
          checked={draft.crossesMidnight}
          onChange={(checked) => updateTime({ crossesMidnight: checked })}
        />
        <ToggleRow
          label="属于休息"
          detail="休息班次不计入工作日"
          checked={draft.isRest}
          onChange={(checked) =>
            setDraft({
              ...draft,
              isRest: checked,
              countsAsWork: !checked,
              defaultHours: checked ? 0 : draft.defaultHours,
            })
          }
        />
        {!draft.isRest && (
          <ToggleRow
            label="计入工作工时"
            detail="可用于备班等不计工时班次"
            checked={draft.countsAsWork}
            onChange={(checked) =>
              setDraft({ ...draft, countsAsWork: checked })
            }
          />
        )}
        <NumberSetting
          label="默认工作时长"
          value={draft.defaultHours}
          unit="h"
          onChange={(defaultHours) => setDraft({ ...draft, defaultHours })}
        />
        <ColorPicker
          colors={SHIFT_COLORS}
          value={draft.color}
          onChange={(color) => setDraft({ ...draft, color })}
        />
        <label className="wide-field">
          <span>备注（可选）</span>
          <input
            value={draft.note ?? ""}
            onChange={(event) =>
              setDraft({ ...draft, note: event.target.value })
            }
          />
        </label>
        <div className="sheet-actions">
          <button className="secondary-button" onClick={onClose}>
            取消
          </button>
          <button
            className="primary-button"
            disabled={!draft.name.trim() || !draft.shortName.trim()}
            onClick={() =>
              onSave({
                ...draft,
                name: draft.name.trim(),
                shortName: draft.shortName.trim(),
              })
            }
          >
            保存班次
          </button>
        </div>
      </section>
    </div>
  );
}
function TagEditor({
  value,
  onClose,
  onSave,
}: {
  value?: DutyTag;
  onClose: () => void;
  onSave: (tag: DutyTag) => void;
}) {
  const [draft, setDraft] = useState<DutyTag>(
    value ?? {
      id: makeId("tag"),
      name: "新标签",
      shortName: "新",
      color: TAG_COLORS[0],
    },
  );
  return (
    <div className="modal-backdrop" onMouseDown={onClose}>
      <section
        className="dialog-card glass-panel entity-editor"
        onMouseDown={(event) => event.stopPropagation()}
      >
        <div className="sheet-header">
          <div>
            <p className="eyebrow">职责信息</p>
            <h2>{value ? "编辑标签" : "创建标签"}</h2>
          </div>
          <button
            aria-label="关闭弹窗"
            className="close-button"
            onClick={onClose}
          >
            ×
          </button>
        </div>
        <div className="form-grid">
          <label>
            <span>名称</span>
            <input
              value={draft.name}
              onChange={(event) =>
                setDraft({ ...draft, name: event.target.value })
              }
            />
          </label>
          <label>
            <span>日历简称</span>
            <input
              maxLength={6}
              value={draft.shortName}
              onChange={(event) =>
                setDraft({ ...draft, shortName: event.target.value })
              }
            />
          </label>
        </div>
        <ColorPicker
          colors={TAG_COLORS}
          value={draft.color}
          onChange={(color) => setDraft({ ...draft, color })}
        />
        <div className="sheet-actions">
          <button className="secondary-button" onClick={onClose}>
            取消
          </button>
          <button
            className="primary-button"
            disabled={!draft.name.trim() || !draft.shortName.trim()}
            onClick={() =>
              onSave({
                ...draft,
                name: draft.name.trim(),
                shortName: draft.shortName.trim(),
              })
            }
          >
            保存标签
          </button>
        </div>
      </section>
    </div>
  );
}
function ColorPicker({
  colors,
  value,
  onChange,
}: {
  colors: string[];
  value: string;
  onChange: (color: string) => void;
}) {
  return (
    <div className="color-picker">
      <span>显示颜色</span>
      <div>
        {colors.map((color) => (
          <button
            key={color}
            className={value === color ? "active" : ""}
            style={{ background: color }}
            onClick={() => onChange(color)}
            aria-label={color}
          />
        ))}
      </div>
    </div>
  );
}
function NumberModal({
  title,
  value,
  unit,
  onClose,
  onSave,
}: {
  title: string;
  value: number;
  unit: string;
  onClose: () => void;
  onSave: (value: number) => void;
}) {
  const [text, setText] = useState(String(value));
  const parsed = Number(text);
  return (
    <div className="modal-backdrop" onMouseDown={onClose}>
      <section
        className="number-editor-card glass-panel"
        onMouseDown={(event) => event.stopPropagation()}
      >
        <div className="sheet-header">
          <h2>{title}</h2>
          <button
            aria-label="关闭弹窗"
            className="close-button"
            onClick={onClose}
          >
            ×
          </button>
        </div>
        <label className="number-editor-input">
          <span>输入新数值</span>
          <div>
            <input
              autoFocus
              inputMode="decimal"
              value={text}
              onChange={(event) =>
                setText(event.target.value.replace(/[^0-9.]/g, ""))
              }
            />
            <b>{unit}</b>
          </div>
        </label>
        <div className="sheet-actions">
          <button className="secondary-button" onClick={onClose}>
            取消
          </button>
          <button
            className="primary-button"
            disabled={!Number.isFinite(parsed) || parsed < 0}
            onClick={() => onSave(parsed)}
          >
            确定修改
          </button>
        </div>
      </section>
    </div>
  );
}

function DayEditor({
  date,
  record,
  data,
  onClose,
  onSave,
  onRest,
}: {
  date: string;
  record?: DayRecord;
  data: AppData;
  onClose: () => void;
  onSave: (record: DayRecord) => void;
  onRest: () => void;
}) {
  const defaultShift =
    data.shifts.find((shift) => !shift.isRest) ?? data.shifts[0];
  const [draft, setDraft] = useState<DayRecord>(
    record
      ? { ...record }
      : {
          date,
          shiftId: defaultShift.id,
          hours: defaultShift.defaultHours,
          tagIds: [],
          completed: false,
          planned: true,
          source: "manual",
        },
  );
  const formatted = parseDate(date);
  const shift =
    data.shifts.find((item) => item.id === draft.shiftId) ?? defaultShift;
  const manualMode =
    data.work.trackOvertime &&
    (data.work.system === "manual" ||
      data.work.system === "irregular" ||
      (data.work.system === "custom" && data.work.customRule === "manual"));
  function chooseShift(next: Shift) {
    setDraft((current) => ({
      ...current,
      shiftId: next.id,
      hours: next.defaultHours,
      completed: next.isRest ? false : current.completed,
      source: "manual",
    }));
  }
  return (
    <div className="modal-backdrop" onMouseDown={onClose}>
      <section
        className="bottom-sheet glass-panel day-editor-v2"
        onMouseDown={(event) => event.stopPropagation()}
      >
        <div className="sheet-grabber" />
        <div className="sheet-header">
          <div>
            <p className="eyebrow">{date}</p>
            <h2>
              {formatted.getMonth() + 1}月{formatted.getDate()}日 · 周
              {WEEKDAYS[(formatted.getDay() + 6) % 7]}
            </h2>
          </div>
          <button
            aria-label="关闭日期编辑"
            className="close-button"
            onClick={onClose}
          >
            ×
          </button>
        </div>
        <p className="editor-section-label">主要班次</p>
        <div className="shift-picker custom-shift-picker">
          {orderedShifts(data.shifts).map((item) => (
            <button
              key={item.id}
              className={draft.shiftId === item.id ? "active" : ""}
              style={colorStyle(item.color)}
              onClick={() => chooseShift(item)}
            >
              <span>{item.shortName}</span>
              {item.name}
            </button>
          ))}
        </div>
        {data.tags.length > 0 && (
          <>
            <p className="editor-section-label">职责标签 · 可多选</p>
            <div className="day-tag-picker">
              {data.tags.map((tag) => (
                <button
                  key={tag.id}
                  className={draft.tagIds.includes(tag.id) ? "active" : ""}
                  style={colorStyle(tag.color)}
                  onClick={() =>
                    setDraft((current) => ({
                      ...current,
                      tagIds: current.tagIds.includes(tag.id)
                        ? current.tagIds.filter((id) => id !== tag.id)
                        : [...current.tagIds, tag.id],
                    }))
                  }
                >
                  {tag.shortName}
                </button>
              ))}
            </div>
          </>
        )}
        {!shift.isRest && (
          <ToggleRow
            label="班次已完成"
            detail="过去日期自动计入；今天或未来可手动确认"
            checked={draft.completed}
            onChange={(completed) => setDraft({ ...draft, completed })}
          />
        )}{" "}
        {data.work.trackHours && (
          <div className="editor-grid">
            <label className="field">
              <span>实际 / 计划工时</span>
              <div>
                <input
                  type="number"
                  step="0.5"
                  min="0"
                  value={draft.hours}
                  onChange={(event) =>
                    setDraft({
                      ...draft,
                      hours: Number(event.target.value) || 0,
                    })
                  }
                />
                <b>小时</b>
              </div>
            </label>
            {manualMode && (
              <label className="field">
                <span>手动额外工时</span>
                <div>
                  <input
                    type="number"
                    step="0.5"
                    min="0"
                    value={draft.manualOvertime ?? 0}
                    onChange={(event) =>
                      setDraft({
                        ...draft,
                        manualOvertime: Number(event.target.value) || 0,
                      })
                    }
                  />
                  <b>小时</b>
                </div>
              </label>
            )}
          </div>
        )}
        <label className="field note-field">
          <span>
            时间：
            {shift.startTime && shift.endTime
              ? `${shift.startTime}–${shift.endTime}${shift.crossesMidnight ? "（跨天）" : ""}`
              : "未设置"}{" "}
            · 备注
          </span>
          <input
            placeholder="例如：临时换班、培训…"
            value={draft.note ?? ""}
            onChange={(event) =>
              setDraft({ ...draft, note: event.target.value })
            }
          />
        </label>
        <div className="warning-note">
          <Icon name="spark" />
          <span>
            这里只修改当天，不会改变后续循环。要改变未来，请使用“修改循环”。
          </span>
        </div>
        <div className="sheet-actions">
          <button className="delete-button" onClick={onRest}>
            <Icon name="trash" />
            设为休息
          </button>
          <button
            className="primary-button"
            onClick={() =>
              onSave({ ...draft, source: "manual", planned: true })
            }
          >
            保存当天
          </button>
        </div>
      </section>
    </div>
  );
}

function BatchEditor({
  dates,
  data,
  onClose,
  onSave,
}: {
  dates: string[];
  data: AppData;
  onClose: () => void;
  onSave: (shiftId: string, hours: number) => void;
}) {
  const shiftChoices = orderedShifts(data.shifts);
  const initial = shiftChoices[0];
  const [shiftId, setShiftId] = useState(initial.id);
  const selected = data.shifts.find((shift) => shift.id === shiftId) ?? initial;
  const [hours, setHours] = useState(initial.defaultHours);
  return (
    <div className="modal-backdrop" onMouseDown={onClose}>
      <section
        className="bottom-sheet glass-panel"
        onMouseDown={(event) => event.stopPropagation()}
      >
        <div className="sheet-grabber" />
        <div className="sheet-header">
          <div>
            <p className="eyebrow">批量修改 · {dates.length} 天</p>
            <h2>统一设置所选日期</h2>
          </div>
          <button
            aria-label="关闭弹窗"
            className="close-button"
            onClick={onClose}
          >
            ×
          </button>
        </div>
        <div className="shift-picker custom-shift-picker">
          {shiftChoices.map((shift) => (
            <button
              key={shift.id}
              className={shiftId === shift.id ? "active" : ""}
              style={colorStyle(shift.color)}
              onClick={() => {
                setShiftId(shift.id);
                setHours(shift.defaultHours);
              }}
            >
              <span>{shift.shortName}</span>
              {shift.name}
            </button>
          ))}
        </div>
        {data.work.trackHours && (
          <NumberSetting
            label="统一工时"
            value={hours}
            unit="h"
            onChange={setHours}
          />
        )}
        <div className="warning-note">
          <Icon name="spark" />
          <span>
            只覆盖 {dates[0]} 至 {dates[dates.length - 1]}
            ，其他日期和未来循环不变。
          </span>
        </div>
        <div className="sheet-actions">
          <button className="secondary-button" onClick={onClose}>
            返回
          </button>
          <button
            className="primary-button"
            onClick={() => onSave(selected.id, hours)}
          >
            确认修改 {dates.length} 天
          </button>
        </div>
      </section>
    </div>
  );
}

function ScheduleGenerator({
  data,
  initialYear,
  onClose,
  onGenerate,
}: {
  data: AppData;
  initialYear: number;
  onClose: () => void;
  onGenerate: (cycle: ActiveCycle, saveTemplate: boolean) => void;
}) {
  const today = dateKey(new Date());
  const [cycleIds, setCycleIds] = useState<string[]>(
    data.activeCycle?.shiftIds ?? [],
  );
  const [name, setName] = useState(data.activeCycle?.name ?? "我的循环");
  const [startDate, setStartDate] = useState(
    data.activeCycle?.startDate ??
      (today.startsWith(`${initialYear}-`) ? today : `${initialYear}-01-01`),
  );
  const [saveTemplate, setSaveTemplate] = useState(false);
  const usableShifts = orderedShifts(
    data.shifts.filter((shift) => shift.id !== "shift-leave"),
  );
  const recommendedCategory =
    data.careerPreset === "medical"
      ? "medical"
      : data.careerPreset === "transport" || data.careerPreset === "service"
        ? "threeShift"
        : "manufacturing";
  const recommendedTemplates = data.cycleTemplates.filter(
    (template) => template.builtIn && template.category === recommendedCategory,
  );
  const personalTemplates = data.cycleTemplates.filter(
    (template) => !template.builtIn,
  );
  const visibleTemplates = [
    ...recommendedTemplates.slice(0, 4),
    ...personalTemplates,
  ].filter((template) =>
    template.shiftIds.every((id) =>
      data.shifts.some((shift) => shift.id === id),
    ),
  );
  function chooseTemplate(template: CycleTemplate) {
    setCycleIds([...template.shiftIds]);
    setName(template.name);
  }
  return (
    <div className="modal-backdrop" onMouseDown={onClose}>
      <section
        className="dialog-card glass-panel generator-v2"
        onMouseDown={(event) => event.stopPropagation()}
      >
        <div className="sheet-header">
          <div>
            <p className="eyebrow">循环排班</p>
            <h2>按班次序列不断重复</h2>
          </div>
          <button
            aria-label="关闭循环排班"
            className="close-button"
            onClick={onClose}
          >
            ×
          </button>
        </div>
        <div className="cycle-template-head">
          <span>推荐与我的模板</span>
          <small>已按工作类型筛选，选中后仍可修改</small>
        </div>
        <div className="cycle-template-grid">
          {visibleTemplates.map((template) => (
            <button
              key={template.id}
              className={
                cycleIds.join() === template.shiftIds.join() ? "active" : ""
              }
              onClick={() => chooseTemplate(template)}
            >
              <strong>{template.name}</strong>
              <small>{template.caption}</small>
            </button>
          ))}
        </div>
        <div className="cycle-builder-head">
          <span>当前循环 · {cycleIds.length} 天</span>
          <div>
            <button onClick={() => setCycleIds((items) => items.slice(0, -1))}>
              撤销
            </button>
            <button onClick={() => setCycleIds([])}>清空</button>
          </div>
        </div>
        <div className="cycle-preview-line cycle-builder-preview">
          {cycleIds.length ? (
            cycleIds.map((id, index) => {
              const shift = data.shifts.find((item) => item.id === id);
              return (
                shift && (
                  <span key={`${id}-${index}`} style={colorStyle(shift.color)}>
                    <small>{index + 1}</small>
                    {shift.shortName}
                  </span>
                )
              );
            })
          ) : (
            <p>请依次添加班次</p>
          )}
        </div>
        <div className="cycle-controls custom-cycle-controls">
          {usableShifts.map((shift) => (
            <button
              key={shift.id}
              style={colorStyle(shift.color)}
              onClick={() =>
                cycleIds.length < 62 &&
                setCycleIds((items) => [...items, shift.id])
              }
            >
              <b>＋ {shift.shortName}</b>
              <span>{shift.name}</span>
            </button>
          ))}
        </div>
        <div className="form-grid generator-fields">
          <label>
            <span>循环名称</span>
            <input
              value={name}
              onChange={(event) => setName(event.target.value)}
            />
          </label>
          <label>
            <span>生效日（第 1 天）</span>
            <input
              type="date"
              value={startDate}
              onChange={(event) => setStartDate(event.target.value)}
            />
          </label>
        </div>
        <ToggleRow
          label="保存为“我的循环”"
          detail="以后可以一键再次使用"
          checked={saveTemplate}
          onChange={setSaveTemplate}
        />
        <div className="warning-note">
          <Icon name="spark" />
          <span>
            {startDate}{" "}
            之前记录不变；当天及之后会按新循环生成。以后浏览其他年份时会自动延续，不会在年底停止。
          </span>
        </div>
        <div className="sheet-actions">
          <button className="secondary-button" onClick={onClose}>
            取消
          </button>
          <button
            className="primary-button"
            disabled={!cycleIds.length || !startDate || !name.trim()}
            onClick={() =>
              onGenerate(
                {
                  id: makeId("cycle"),
                  name: name.trim(),
                  startDate,
                  shiftIds: cycleIds,
                },
                saveTemplate,
              )
            }
          >
            从生效日开始
          </button>
        </div>
      </section>
    </div>
  );
}
