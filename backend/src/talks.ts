import { es, IDX } from "./elastic";
import { nowMs } from "./config";
import { chatJSON, reasonCache } from "./llm";
import { traced } from "./otel";
import { getProfile } from "./profile";
import { savedTalkIds, swipesOf } from "./swipes";
import { freeBlocks, ms, overlaps } from "./time";
import { acceptedMeetupsFor } from "./meetups";
import { matchedPids } from "./matches";
import type { Profile, Schedule, ScheduleItem, Talk, TalkCard } from "./types";

export async function getTalks(tids: string[]): Promise<Map<string, Talk>> {
  const out = new Map<string, Talk>();
  if (!tids.length) return out;
  const r = await es().mget<Talk>({ index: IDX.talks, ids: [...new Set(tids)] });
  for (const d of r.docs) if ("found" in d && d.found && d._source) out.set(d._id, d._source);
  return out;
}

function preferredLevel(p: Profile): Talk["level"] {
  const r = `${p.role ?? ""} ${p.summary ?? ""}`.toLowerCase();
  if (/student|junior|intern|new to|learning/.test(r)) return "beginner";
  if (/staff|principal|senior|lead|architect|maintainer|founder/.test(r)) return "advanced";
  return "intermediate";
}

const LEVELS = ["beginner", "intermediate", "advanced"];
const levelFit = (want: Talk["level"], got: Talk["level"]) => 1 - Math.abs(LEVELS.indexOf(want) - LEVELS.indexOf(got)) / 2;

/** Hybrid search: semantic on content + keyword on topics/title/abstract, fused with RRF. */
async function hybridTalkSearch(queryText: string, topics: string[], exclude: string[], size: number): Promise<Talk[]> {
  const filter = [{ range: { start: { gte: new Date(nowMs()).toISOString() } } }];
  const mustNot = exclude.length ? [{ ids: { values: exclude } }] : [];
  const lexical = {
    bool: {
      should: [
        ...(topics.length ? [{ terms: { topics, boost: 2 } }] : []),
        { multi_match: { query: queryText, fields: ["title^2", "abstract"] } },
      ],
      minimum_should_match: 1,
      filter,
      must_not: mustNot,
    },
  };
  const semantic = { bool: { must: [{ semantic: { field: "content", query: queryText } }], filter, must_not: mustNot } };

  return traced("elastic.talks.hybrid", { "orbit.topics": topics.join(","), "orbit.size": size }, async (span) => {
    try {
      const r = await es().search<Talk>({
        index: IDX.talks,
        size,
        retriever: {
          rrf: {
            retrievers: [{ standard: { query: semantic as any } }, { standard: { query: lexical as any } }],
            rank_window_size: 50,
          },
        } as any,
      });
      span.setAttribute("orbit.search.mode", "rrf");
      return r.hits.hits.map((h) => h._source!);
    } catch (err) {
      // Older clusters / licenses without RRF: fall back to a single bool query combining both.
      span.setAttribute("orbit.search.mode", "bool_fallback");
      span.recordException(err as Error);
      const r = await es().search<Talk>({
        index: IDX.talks,
        size,
        query: { bool: { should: [semantic.bool.must[0], ...lexical.bool.should], filter, must_not: mustNot } } as any,
      });
      return r.hits.hits.map((h) => h._source!);
    }
  });
}

function templateTalkReason(p: Profile, t: Talk): string {
  const shared = t.topics.filter((x) => p.topics.includes(x));
  if (shared.length) return `Covers ${shared.slice(0, 2).join(" and ")}, which matches your work on ${trim(p.working_on, 60)}`;
  return `Related to what you're looking for: ${trim(p.looking_for, 70)}`;
}

const trim = (s: string, n: number) => {
  const t = s.replace(/\s+/g, " ").trim().replace(/\.$/, "");
  return t.length > n ? t.slice(0, n - 1).replace(/\s+\S*$/, "") + "…" : t.charAt(0).toLowerCase() + t.slice(1);
};

async function talkReasons(p: Profile, talks: Talk[]): Promise<Map<string, string>> {
  const out = new Map<string, string>();
  const missing = talks.filter((t) => {
    const c = reasonCache.get(`talk:${p.pid}:${t.tid}`);
    if (c) out.set(t.tid, c);
    return !c;
  });
  if (missing.length) {
    const llm = await chatJSON<{ reasons: Record<string, string> }>(
      "talk_reasons",
      `You write one-line reasons why a conference talk fits a specific attendee.
Return JSON {"reasons": {"<tid>": "<reason>"}} with one entry per talk.
Each reason: under 18 words, second person ("You…"), concrete, cite something from their profile. No hype words.`,
      JSON.stringify({
        attendee: { role: p.role, working_on: p.working_on, looking_for: p.looking_for, topics: p.topics },
        talks: missing.map((t) => ({ tid: t.tid, title: t.title, abstract: t.abstract, topics: t.topics })),
      }),
    );
    for (const t of missing) {
      const r = llm?.reasons?.[t.tid]?.trim() || templateTalkReason(p, t);
      reasonCache.set(`talk:${p.pid}:${t.tid}`, r);
      out.set(t.tid, r);
    }
  }
  return out;
}

export async function recommendTalks(pid: string, limit = 10): Promise<TalkCard[]> {
  const p = await getProfile(pid);
  const swiped = await swipesOf(pid, "talk");
  const likedIds = [...swiped.entries()].filter(([, d]) => d !== "left").map(([t]) => t);
  const mustIds = [...swiped.entries()].filter(([, d]) => d === "up").map(([t]) => t);
  const liked = await getTalks(likedIds);

  // Feedback loop: talks you saved pull the query (and topic set) toward them.
  const likedList = [...liked.values()].slice(-5);
  const queryText = [p.working_on, p.looking_for, ...likedList.map((t) => t.title)].join(". ");
  const likedTopics = likedList.flatMap((t) => t.topics);
  const topics = [...new Set([...p.topics, ...likedTopics])];

  const candidates = await hybridTalkSearch(queryText, topics, [...swiped.keys()], Math.max(limit * 3, 20));

  // Re-rank: RRF position + level fit + talks your matches saved.
  const want = preferredLevel(p);
  const matchSaved = new Set<string>();
  for (const other of await matchedPids(pid)) for (const t of (await savedTalkIds(other)).saved) matchSaved.add(t);
  const ranked = candidates
    .map((t, i) => ({
      t,
      score: 1 - i / candidates.length + 0.15 * levelFit(want, t.level) + (matchSaved.has(t.tid) ? 0.2 : 0),
    }))
    .sort((a, b) => b.score - a.score)
    .slice(0, limit)
    .map((x) => x.t);

  const must = [...(await getTalks(mustIds)).values()];
  const reasons = await talkReasons(p, ranked);
  return ranked.map((t) => {
    const clash = must.find((m) => overlaps(m, t));
    return { ...t, reason: reasons.get(t.tid)!, clashes_with: clash ? { tid: clash.tid, title: clash.title } : null };
  });
}

export async function getSchedule(pid: string): Promise<Schedule & { meetups: unknown[] }> {
  await getProfile(pid);
  const { saved, must } = await savedTalkIds(pid);
  const talks = [...(await getTalks(saved)).values()].sort((a, b) => ms(a.start) - ms(b.start));
  const items: ScheduleItem[] = talks.map((t) => ({
    tid: t.tid,
    title: t.title,
    room: t.room,
    start: t.start,
    end: t.end,
    must: must.has(t.tid),
    clash: talks.some((o) => o.tid !== t.tid && overlaps(o, t)),
  }));
  const meetups = await acceptedMeetupsFor(pid);
  const free = freeBlocks([...items, ...meetups]);
  return { pid, items, free, meetups };
}
