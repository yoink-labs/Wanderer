const DAY_MS = 86_400_000;

export function parseDateOnly(value: string | null | undefined): Date | null {
  if (!value) return null;
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) return null;
  return new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])));
}

export function dateOnly(date: Date): string {
  return date.toISOString().slice(0, 10);
}

export function todayKey(): string {
  return dateOnly(new Date());
}

export function addDays(value: string, days: number): string {
  const date = parseDateOnly(value) ?? new Date();
  return dateOnly(new Date(date.getTime() + days * DAY_MS));
}

export function daysBetween(start: string, end: string): number {
  const a = parseDateOnly(start);
  const b = parseDateOnly(end);
  if (!a || !b) return 0;
  return Math.round((b.getTime() - a.getTime()) / DAY_MS);
}

export function dayCount(start: string | null, end: string | null): number {
  if (!start || !end) return 0;
  return Math.max(1, daysBetween(start, end) + 1);
}

export function rangeDays(start: string, end: string): string[] {
  const count = Math.max(0, daysBetween(start, end) + 1);
  return Array.from({ length: Math.min(count, 366) }, (_, index) => addDays(start, index));
}

export type TripPhase = "upcoming" | "inProgress" | "past";

export function tripPhase(start: string | null, end: string | null, now = new Date()): TripPhase {
  const today = dateOnly(now);
  if (!start || !end) return "upcoming";
  if (today < start) return "upcoming";
  if (today > end) return "past";
  return "inProgress";
}

export function daysUntil(start: string | null, now = new Date()): number | null {
  const date = parseDateOnly(start);
  if (!date) return null;
  const today = new Date(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate()));
  return Math.round((date.getTime() - today.getTime()) / DAY_MS);
}

export function fmtDate(value: string | null | undefined, options: Intl.DateTimeFormatOptions = {}): string {
  const date = parseDateOnly(value);
  if (!date) return "Dates not set";
  return new Intl.DateTimeFormat(undefined, {
    month: "short",
    day: "numeric",
    timeZone: "UTC",
    ...options,
  }).format(date);
}

export function fmtDateLong(value: string | null | undefined): string {
  return fmtDate(value, { weekday: "long", month: "long", day: "numeric" });
}

export function fmtDateRange(start: string | null, end: string | null): string {
  if (!start && !end) return "Dates not set";
  if (!start) return `Until ${fmtDate(end)}`;
  if (!end) return `From ${fmtDate(start)}`;
  if (start === end) return fmtDate(start, { weekday: "short", month: "short", day: "numeric" });
  const startDate = parseDateOnly(start);
  const endDate = parseDateOnly(end);
  if (!startDate || !endDate) return "Dates not set";
  const sameMonth = startDate.getUTCMonth() === endDate.getUTCMonth() && startDate.getUTCFullYear() === endDate.getUTCFullYear();
  return sameMonth
    ? `${fmtDate(start, { month: "short", day: "numeric" })} – ${fmtDate(end, { day: "numeric" })}, ${endDate.getUTCFullYear()}`
    : `${fmtDate(start)} – ${fmtDate(end, { year: "numeric" })}`;
}

export function countdownLabel(start: string | null, end: string | null, now = new Date()): string {
  const phase = tripPhase(start, end, now);
  const days = daysUntil(start, now);
  if (phase === "inProgress") {
    const total = dayCount(start, end);
    const index = start ? Math.max(0, daysBetween(start, dateOnly(now))) : 0;
    return `Day ${Math.min(index + 1, total)} of ${total}`;
  }
  if (phase === "past") return "Past trip";
  if (days == null) return "Upcoming";
  if (days <= 0) return "Starts today";
  if (days === 1) return "Starts tomorrow";
  return `Starts in ${days} days`;
}

export function weekday(value: string | null): string {
  const date = parseDateOnly(value);
  if (!date) return "";
  return new Intl.DateTimeFormat(undefined, { weekday: "short", timeZone: "UTC" }).format(date);
}

function zonedParts(date: Date, timeZone: string): Record<string, number> {
  const formatter = new Intl.DateTimeFormat("en-US", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
  });
  const parts = formatter.formatToParts(date);
  const map: Record<string, number> = {};
  for (const part of parts) if (part.type !== "literal") map[part.type] = Number(part.value);
  return map;
}

/** Convert a wall-clock date + time in an IANA timezone to a UTC Date. */
export function zonedTimeToUtc(dateKey: string, time = "00:00", timeZone = "UTC"): Date {
  const [year, month, day] = dateKey.split("-").map(Number);
  const [hour, minute] = time.split(":").map(Number);
  const desired = Date.UTC(year || 1970, (month || 1) - 1, day || 1, hour || 0, minute || 0, 0);
  let stamp = desired;
  for (let i = 0; i < 3; i += 1) {
    const parts = zonedParts(new Date(stamp), timeZone);
    const actual = Date.UTC(
      parts.year ?? 1970,
      (parts.month ?? 1) - 1,
      parts.day ?? 1,
      parts.hour ?? 0,
      parts.minute ?? 0,
      parts.second ?? 0,
    );
    stamp += desired - actual;
  }
  return new Date(stamp);
}

export function isoFromZoned(dateKey: string, time: string, timeZone: string): string {
  return zonedTimeToUtc(dateKey, time, timeZone).toISOString();
}

export function formatInZone(value: string | null | undefined, timeZone: string, options: Intl.DateTimeFormatOptions): string {
  if (!value) return "";
  const date = new Date(value);
  if (!Number.isFinite(date.getTime())) return "";
  return new Intl.DateTimeFormat(undefined, { timeZone, ...options }).format(date);
}

export function dateKeyInZone(value: string | null | undefined, timeZone: string): string | null {
  if (!value) return null;
  const date = new Date(value);
  if (!Number.isFinite(date.getTime())) return null;
  const parts = zonedParts(date, timeZone);
  return `${String(parts.year).padStart(4, "0")}-${String(parts.month).padStart(2, "0")}-${String(parts.day).padStart(2, "0")}`;
}

export function timeInZone(value: string | null | undefined, timeZone: string): string {
  return formatInZone(value, timeZone, { hour: "numeric", minute: "2-digit" });
}

export function timeRangeInZone(start: string | null | undefined, end: string | null | undefined, timeZone: string): string {
  const a = timeInZone(start, timeZone);
  const b = timeInZone(end, timeZone);
  if (a && b) return `${a} – ${b}`;
  return a || b;
}

export function localInputValue(value: string | null | undefined, timeZone: string): string {
  if (!value) return "";
  const date = new Date(value);
  if (!Number.isFinite(date.getTime())) return "";
  const parts = zonedParts(date, timeZone);
  return `${String(parts.year).padStart(4, "0")}-${String(parts.month).padStart(2, "0")}-${String(parts.day).padStart(2, "0")}T${String(parts.hour).padStart(2, "0")}:${String(parts.minute).padStart(2, "0")}`;
}

export function fromLocalInput(value: string, timeZone: string): string | null {
  if (!value) return null;
  const [date, time] = value.split("T");
  return isoFromZoned(date, time || "00:00", timeZone);
}

export function nowInputValue(): string {
  const date = new Date();
  const pad = (value: number) => String(value).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

export function sameDayInZone(a: string | null | undefined, b: string | null | undefined, timeZone: string): boolean {
  return dateKeyInZone(a, timeZone) === dateKeyInZone(b, timeZone);
}

export function formatDuration(fromIso: string | null, toIso: string | null): string | null {
  if (!fromIso || !toIso) return null;
  const a = Date.parse(fromIso);
  const b = Date.parse(toIso);
  if (!Number.isFinite(a) || !Number.isFinite(b) || b <= a) return null;
  const minutes = Math.round((b - a) / 60000);
  if (minutes >= 24 * 60) {
    const days = Math.round(minutes / (24 * 60));
    return days === 1 ? "1 day" : `${days} days`;
  }
  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  if (!hours) return `${rest}m`;
  return rest ? `${hours}h ${rest}m` : `${hours}h`;
}

export function estimatedTimezone(): string {
  const zone = Intl.DateTimeFormat().resolvedOptions().timeZone;
  return zone || "UTC";
}

export function timezoneOptions(): string[] {
  const intl = Intl as unknown as { supportedValuesOf?: (key: string) => string[] };
  const zones = intl.supportedValuesOf ? intl.supportedValuesOf("timeZone") : [];
  const fallback = [
    "UTC", "Europe/London", "Europe/Paris", "Europe/Lisbon", "Europe/Madrid",
    "Europe/Rome", "Europe/Berlin", "America/New_York", "America/Chicago",
    "America/Denver", "America/Los_Angeles", "America/Mexico_City",
    "America/Sao_Paulo", "Asia/Tokyo", "Asia/Seoul", "Asia/Shanghai",
    "Asia/Singapore", "Asia/Bangkok", "Asia/Kolkata", "Asia/Dubai",
    "Australia/Sydney", "Pacific/Auckland",
  ];
  return Array.from(new Set(["UTC", ...fallback, ...zones]));
}

export function wallTimeInZone(value: string | null | undefined, timeZone: string): string {
  if (!value) return "";
  const date = new Date(value);
  if (!Number.isFinite(date.getTime())) return "";
  return new Intl.DateTimeFormat("en-GB", {
    timeZone,
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).format(date);
}
