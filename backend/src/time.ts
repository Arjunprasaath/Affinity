import { nowMs } from "./config";
import type { TimeBlock } from "./types";

// The conference runs in America/Denver (MST, UTC-7 in November).
export const OFFSET = "-07:00";
const OFFSET_MS = 7 * 60 * 60 * 1000;

export const CONFERENCE_DAYS = ["2026-11-10", "2026-11-11", "2026-11-12"];
export const SLOTS: Record<number, [string, string]> = {
  1: ["10:00", "10:35"],
  2: ["11:00", "11:35"],
  3: ["14:00", "14:35"],
  4: ["15:30", "16:05"],
};
export const DAY_START = "09:00";
export const DAY_END = "18:00";

export const iso = (date: string, hhmm: string) => `${date}T${hhmm}:00${OFFSET}`;
export const ms = (isoStr: string) => Date.parse(isoStr);

/** Format epoch ms as an ISO string in conference local time (with -07:00). */
export function toLocalIso(t: number): string {
  return new Date(t - OFFSET_MS).toISOString().slice(0, 19) + OFFSET;
}

/** "3:40 PM" in conference local time. */
export function clock(isoStr: string): string {
  const d = new Date(ms(isoStr) - OFFSET_MS);
  let h = d.getUTCHours();
  const m = d.getUTCMinutes().toString().padStart(2, "0");
  const ampm = h >= 12 ? "PM" : "AM";
  h = h % 12 || 12;
  return `${h}:${m} ${ampm}`;
}

/** "Tue" etc. in conference local time. */
export function weekday(isoStr: string): string {
  return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][new Date(ms(isoStr) - OFFSET_MS).getUTCDay()];
}

export const overlaps = (a: TimeBlock, b: TimeBlock) => ms(a.start) < ms(b.end) && ms(b.start) < ms(a.end);

/** Gaps of at least minMinutes between busy blocks inside each conference day's window, from "now" on. */
export function freeBlocks(busy: TimeBlock[], minMinutes = 20): TimeBlock[] {
  const out: TimeBlock[] = [];
  const now = nowMs();
  for (const day of CONFERENCE_DAYS) {
    const dayStart = Math.max(ms(iso(day, DAY_START)), now);
    const dayEnd = ms(iso(day, DAY_END));
    if (dayStart >= dayEnd) continue;
    const todays = busy
      .map((b) => [ms(b.start), ms(b.end)] as [number, number])
      .filter(([s, e]) => e > dayStart && s < dayEnd)
      .sort((x, y) => x[0] - y[0]);
    let cursor = dayStart;
    for (const [s, e] of todays) {
      if (s - cursor >= minMinutes * 60000) out.push({ start: toLocalIso(cursor), end: toLocalIso(s) });
      cursor = Math.max(cursor, e);
    }
    if (dayEnd - cursor >= minMinutes * 60000) out.push({ start: toLocalIso(cursor), end: toLocalIso(dayEnd) });
  }
  return out;
}

/** Intersection of two lists of free blocks, keeping overlaps of at least minMinutes. */
export function intersectBlocks(a: TimeBlock[], b: TimeBlock[], minMinutes = 15): TimeBlock[] {
  const out: TimeBlock[] = [];
  for (const x of a) {
    for (const y of b) {
      const s = Math.max(ms(x.start), ms(y.start));
      const e = Math.min(ms(x.end), ms(y.end));
      if (e - s >= minMinutes * 60000) out.push({ start: toLocalIso(s), end: toLocalIso(e) });
    }
  }
  return out.sort((p, q) => ms(p.start) - ms(q.start));
}
