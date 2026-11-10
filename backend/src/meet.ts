import { nowMs } from "./config";
import { forbidden } from "./errors";
import { getMatchDoc } from "./matches";
import { meetupsBetween } from "./meetups";
import { getProfile } from "./profile";
import { getSchedule } from "./talks";
import { placeNear } from "./data";
import { clock, intersectBlocks, ms, toLocalIso, weekday } from "./time";
import { traced } from "./otel";
import type { ScheduleItem, TimeBlock } from "./types";

interface Suggestion {
  kind: "after_shared_talk" | "free_overlap";
  place: string;
  start: string;
  end: string;
  label: string;
}

/** Split free blocks into back-to-back 1-hour slots, dropping leftovers shorter than an hour. */
function hourSlots(blocks: TimeBlock[]): TimeBlock[] {
  const HOUR = 60 * 60000;
  const out: TimeBlock[] = [];
  for (const b of blocks) {
    for (let t = ms(b.start); t + HOUR <= ms(b.end); t += HOUR) {
      out.push({ start: toLocalIso(t), end: toLocalIso(t + HOUR) });
    }
  }
  return out;
}

/** Room of the last talk that ends at or before `t` that day (where the person is coming from). */
function roomBefore(items: ScheduleItem[], t: number): string | undefined {
  const day = toLocalIso(t).slice(0, 10);
  return items
    .filter((i) => ms(i.end) <= t && i.start.slice(0, 10) === day)
    .sort((a, b) => ms(b.end) - ms(a.end))[0]?.room;
}

/**
 * The partial calendar reveal between two matched people, from a's point of view.
 * Reveals only: talks both saved, times both are free, b's next planned room (unless hidden).
 */
export async function meetView(a: string, b: string) {
  return traced("orbit.meet.view", { "orbit.a": a, "orbit.b": b }, async () => {
    if (!(await getMatchDoc(a, b))) throw forbidden("calendars are only shared between mutual matches");
    const [them, sa, sb, meetups] = await Promise.all([getProfile(b), getSchedule(a), getSchedule(b), meetupsBetween(a, b)]);
    const now = nowMs();

    const bIds = new Set(sb.items.map((i) => i.tid));
    const shared_talks = sa.items
      .filter((i) => bIds.has(i.tid) && ms(i.end) > now)
      .map(({ tid, title, room, start, end }) => ({ tid, title, room, start, end }));

    // Shared free time as 1-hour slots (not whole 9-to-6 stretches).
    const free_overlaps: TimeBlock[] = hourSlots(intersectBlocks(sa.free, sb.free, 60)).slice(0, 8);

    const next = sb.items.find((i) => ms(i.end) > now);
    const their_next =
      them.hide_next_room || !next
        ? null
        : { room: next.room, from: next.start, until: next.end, planned: true };

    const suggestions: Suggestion[] = [];
    for (const t of shared_talks.slice(0, 2)) {
      suggestions.push({
        kind: "after_shared_talk",
        place: `${t.room} door`,
        start: t.end,
        end: toLocalIso(ms(t.end) + 15 * 60000),
        label: `Meet when '${t.title}' ends (${weekday(t.end)} ${clock(t.end)})`,
      });
    }
    for (const f of free_overlaps.slice(0, 4)) {
      const s = ms(f.start);
      const e = ms(f.end); // each slot is already exactly 1 hour
      const fromA = roomBefore(sa.items, s);
      const fromB = roomBefore(sb.items, s);
      suggestions.push({
        kind: "free_overlap",
        place: placeNear(fromA ?? fromB),
        start: f.start,
        end: toLocalIso(e),
        label: `You're both free ${weekday(f.start)} ${clock(f.start)}–${clock(f.end)}`,
      });
    }
    suggestions.sort((x, y) => ms(x.start) - ms(y.start));

    return {
      with: b,
      name: them.name,
      shared_talks,
      free_overlaps,
      their_next,
      suggestions: suggestions.slice(0, 3),
      meetups,
    };
  });
}
