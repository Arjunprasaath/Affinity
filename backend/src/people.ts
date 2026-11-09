import { es, IDX, searchAll } from "./elastic";
import { config } from "./config";
import { chatJSON, reasonCache } from "./llm";
import { traced, matchCounter, swipeCounter } from "./otel";
import { badRequest, notFound } from "./errors";
import { getProfile, getProfiles, interestTopics } from "./profile";
import { getSwipe, putSwipe, savedTalkIds, savedTalksByPerson, swipesOf } from "./swipes";
import { getMatchDoc, matchDocsFor, putMatch } from "./matches";
import { getTalks } from "./talks";
import type { Match, PersonCard, Profile, SwipeDir, TargetType } from "./types";

// ---------- scoring ----------

/** Semantic similarity of `text` against `field` for every profile, min-max normalized to 0..1. */
async function semanticScores(field: "working_on" | "looking_for" | "offering", text: string, excludePid: string) {
  const r = await es().search({
    index: IDX.profiles,
    size: 500,
    _source: ["pid"],
    query: { bool: { must: [{ semantic: { field, query: text } } as any], must_not: [{ term: { pid: excludePid } }] } },
  });
  const raw = new Map<string, number>(r.hits.hits.map((h) => [(h._source as any).pid as string, h._score ?? 0]));
  const vals = [...raw.values()];
  const max = Math.max(...vals, 0);
  const min = Math.min(...vals, max);
  const out = new Map<string, number>();
  for (const [pid, s] of raw) out.set(pid, max === min ? 1 : (s - min) / (max - min));
  return out;
}

const jaccard = (a: string[], b: string[]) => {
  const A = new Set(a);
  const B = new Set(b);
  const inter = [...A].filter((x) => B.has(x)).length;
  const union = new Set([...A, ...B]).size;
  return union ? inter / union : 0;
};

const COMPLEMENT: [string, string][] = [
  ["hiring", "job_hunting"],
  ["finding_contributors", "learning"],
  ["meeting_users", "learning"],
];
const goalsComplement = (a: string[], b: string[]) =>
  COMPLEMENT.some(([x, y]) => (a.includes(x) && b.includes(y)) || (a.includes(y) && b.includes(x)));

export interface Scored {
  other: Profile;
  score: number;
  need_offer: number;
  interests: number;
  talk_overlap: number;
  shared_topics: string[];
  shared_talks: string[];
  complement: boolean;
}

/** Score `me` against every other profile. Reciprocal: need_offer is a geometric mean of both directions. */
export async function scoreAll(me: Profile): Promise<Scored[]> {
  return traced("elastic.people.score", { "orbit.pid": me.pid }, async (span) => {
    const [iNeedTheyOffer, theyNeedIOffer, workSim, everyone, saved] = await Promise.all([
      semanticScores("offering", me.looking_for, me.pid),
      semanticScores("looking_for", me.offering, me.pid),
      semanticScores("working_on", me.working_on, me.pid),
      searchAll<Profile>(
        IDX.profiles,
        {
          bool: {
            must_not: [
              { term: { pid: me.pid } },
              { term: { status: "red" } },
              // Never show you your own older profiles (same GitHub) if you signed up more than once.
              ...(me.github ? [{ term: { github: me.github } }] : []),
            ],
          },
        },
        1000,
      ),
      savedTalksByPerson(),
    ]);
    const mine = saved.get(me.pid) ?? new Set<string>();
    const hasTalks = mine.size > 0;
    const out = everyone.map((other) => {
      const need_offer = Math.sqrt((iNeedTheyOffer.get(other.pid) ?? 0) * (theyNeedIOffer.get(other.pid) ?? 0));
      const shared_topics = interestTopics(me).filter((t) => other.topics.includes(t));
      const interests = 0.5 * jaccard(me.topics, other.topics) + 0.5 * (workSim.get(other.pid) ?? 0);
      const theirs = saved.get(other.pid) ?? new Set<string>();
      const shared_talks = [...mine].filter((t) => theirs.has(t));
      const talk_overlap = Math.min(1, shared_talks.length / Math.max(1, Math.min(mine.size, 4)));
      const complement = goalsComplement(me.here_for, other.here_for);
      const base = hasTalks
        ? 0.45 * need_offer + 0.3 * interests + 0.25 * talk_overlap
        : 0.6 * need_offer + 0.4 * interests;
      const score = Math.min(1, base + (complement ? 0.1 : 0));
      return { other, score, need_offer, interests, talk_overlap, shared_topics, shared_talks, complement };
    });
    span.setAttribute("orbit.candidates", out.length);
    return out.sort((a, b) => b.score - a.score);
  });
}

/** Maximal marginal relevance on topics, so the deck isn't ten near-identical people. */
function diversify(items: Scored[], k: number, lambda = 0.75): Scored[] {
  const pool = [...items];
  const picked: Scored[] = [];
  while (picked.length < k && pool.length) {
    let best = 0;
    let bestVal = -Infinity;
    pool.forEach((c, i) => {
      const sim = picked.length ? Math.max(...picked.map((p) => jaccard(p.other.topics, c.other.topics))) : 0;
      const v = lambda * c.score - (1 - lambda) * sim;
      if (v > bestVal) {
        bestVal = v;
        best = i;
      }
    });
    picked.push(pool.splice(best, 1)[0]);
  }
  return picked;
}

// ---------- reasons ----------

const firstName = (p: Profile) => p.name.split(" ")[0];
const lc = (s: string) => {
  const t = s.replace(/\s+/g, " ").trim().replace(/\.$/, "");
  const short = t.length > 70 ? t.slice(0, 69).replace(/\s+\S*$/, "") + "…" : t;
  return short.charAt(0).toLowerCase() + short.slice(1);
};

export function templatePersonReason(me: Profile, s: Scored): string {
  const parts: string[] = [];
  if (s.need_offer >= 0.5) parts.push(`${firstName(s.other)} is looking for ${lc(s.other.looking_for)}, and you offer ${lc(me.offering)}`);
  else if (s.shared_topics.length) parts.push(`You both work on ${s.shared_topics.slice(0, 2).join(" and ")}`);
  else parts.push(`${firstName(s.other)} is working on ${lc(s.other.working_on)}`);
  if (s.shared_talks.length) parts.push(`you've saved ${s.shared_talks.length} of the same talks`);
  const r = parts.join(" · ");
  return r.charAt(0).toUpperCase() + r.slice(1);
}

async function personReasons(me: Profile, list: Scored[]): Promise<Map<string, string>> {
  const out = new Map<string, string>();
  const missing = list.filter((s) => {
    const c = reasonCache.get(`person:${me.pid}:${s.other.pid}`);
    if (c) out.set(s.other.pid, c);
    return !c;
  });
  if (missing.length) {
    const talkTitles = await getTalks([...new Set(missing.flatMap((s) => s.shared_talks))]);
    const llm = await chatJSON<{ reasons: Record<string, string> }>(
      "person_reasons",
      `You explain why two conference attendees should meet. Return JSON {"reasons": {"<pid>": "<reason>"}}.
Each reason: under 22 words, addressed to the attendee ("you"), refer to the other person by first name.
Lead with what one can do for the other (their needs vs offers), then a shared interest or shared talk if any. Be concrete, no hype.`,
      JSON.stringify({
        attendee: { working_on: me.working_on, looking_for: me.looking_for, offering: me.offering, here_for: me.here_for },
        others: missing.map((s) => ({
          pid: s.other.pid,
          name: s.other.name,
          working_on: s.other.working_on,
          looking_for: s.other.looking_for,
          offering: s.other.offering,
          here_for: s.other.here_for,
          shared_topics: s.shared_topics,
          shared_talks: s.shared_talks.map((t) => talkTitles.get(t)?.title).filter(Boolean),
        })),
      }),
    );
    for (const s of missing) {
      const r = llm?.reasons?.[s.other.pid]?.trim() || templatePersonReason(me, s);
      reasonCache.set(`person:${me.pid}:${s.other.pid}`, r);
      out.set(s.other.pid, r);
    }
  }
  return out;
}

const toCard = (s: Scored, reason: string): PersonCard => ({
  pid: s.other.pid,
  name: s.other.name,
  role: s.other.role,
  company: s.other.company,
  pronouns: s.other.pronouns,
  working_on: s.other.working_on,
  here_for: s.other.here_for,
  topics: s.other.topics,
  shared_topics: s.shared_topics,
  shared_talks_count: s.shared_talks.length,
  score: Math.round(s.score * 100) / 100,
  reason,
  status: s.other.status,
  github: s.other.github,
});

// ---------- endpoints ----------

export async function recommendPeople(pid: string, limit = 10): Promise<PersonCard[]> {
  const me = await getProfile(pid);
  const swiped = await swipesOf(pid, "person");
  // Precise: only people who share one of your interests, or who clearly need what you offer.
  const scored = (await scoreAll(me)).filter(
    (s) => !swiped.has(s.other.pid) && s.other.status !== "red" && (s.shared_topics.length > 0 || s.need_offer >= 0.7),
  );
  const picked = diversify(scored, limit);
  const reasons = await personReasons(me, picked);
  return picked.map((s) => toCard(s, reasons.get(s.other.pid)!));
}

export async function swipe(body: { pid?: string; target_type?: TargetType; target_id?: string; dir?: SwipeDir }) {
  const { pid, target_type, target_id, dir } = body;
  if (!pid || !target_id) throw badRequest("pid and target_id are required");
  if (target_type !== "talk" && target_type !== "person") throw badRequest("target_type must be talk or person");
  if (!dir || !["right", "up", "left"].includes(dir)) throw badRequest("dir must be right, up or left");
  if (target_type === "person" && target_id === pid) throw badRequest("you can't swipe on yourself");

  const me = await getProfile(pid);
  if (target_type === "talk") {
    if (!(await getTalks([target_id])).size) throw notFound(`talk ${target_id}`);
  } else {
    await getProfile(target_id);
  }
  await putSwipe({ pid, target_type, target_id, dir });
  swipeCounter.add(1, { target_type, dir });

  if (target_type === "talk" || dir === "left") return { ok: true };

  // Person right/up swipe: mutual match?
  return traced("orbit.match.check", { "orbit.pid": pid, "orbit.target": target_id }, async (span) => {
    if (await getMatchDoc(pid, target_id)) return { ok: true, match: await matchFor(me, target_id) };

    let s: Scored | undefined;
    let theyLiked = await getSwipe(target_id, "person", pid);
    if (!theyLiked || theyLiked.dir === "left") {
      // Demo helper: seeded personas like you back when the match is strong enough.
      const other = await getProfile(target_id);
      if (other.is_persona) {
        s = (await scoreAll(me)).find((x) => x.other.pid === target_id);
        span.setAttribute("orbit.persona_score", s?.score ?? 0);
        if (s && s.score >= config.personaAutolikeThreshold) {
          theyLiked = await putSwipe({ pid: target_id, target_type: "person", target_id: pid, dir: "right" });
        }
      }
    }
    if (!theyLiked || theyLiked.dir === "left") return { ok: true };

    s ??= (await scoreAll(me)).find((x) => x.other.pid === target_id);
    const reason = s ? (await personReasons(me, [s])).get(target_id)! : "You both want to meet";
    await putMatch(pid, target_id, reason);
    matchCounter.add(1);
    span.setAttribute("orbit.matched", true);
    return { ok: true, match: await matchFor(me, target_id) };
  });
}

async function matchFor(me: Profile, otherPid: string): Promise<Match> {
  const [other, doc] = await Promise.all([getProfile(otherPid), getMatchDoc(me.pid, otherPid)]);
  return {
    pid: other.pid,
    name: other.name,
    role: other.role,
    company: other.company,
    matched_at: doc?.matched_at ?? new Date().toISOString(),
    reason: reasonCache.get(`person:${me.pid}:${other.pid}`) ?? doc?.reason ?? "",
  };
}

export async function listMatches(pid: string): Promise<Match[]> {
  await getProfile(pid);
  const docs = await matchDocsFor(pid);
  const others = await getProfiles(docs.map((d) => d.pids.find((x) => x !== pid)!));
  return docs
    .map((d): Match | null => {
      const o = others.get(d.pids.find((x) => x !== pid)!);
      if (!o || o.status === "red") return null; // invisible people disappear from lists
      return {
        pid: o.pid,
        name: o.name,
        role: o.role,
        company: o.company,
        matched_at: d.matched_at,
        reason: reasonCache.get(`person:${pid}:${o.pid}`) ?? d.reason,
      };
    })
    .filter((m): m is Match => m !== null)
    .sort((a, b) => b.matched_at.localeCompare(a.matched_at));
}

/** Glow tier for each nearby person on the Orbit radar. */
export async function radarTiers(me: string, others: string[]) {
  if (!Array.isArray(others)) throw badRequest("others must be an array of pids");
  const p = await getProfile(me);
  const want = new Set(others.filter((o) => o !== me));
  if (!want.size) return [];
  const [scored, matches] = await Promise.all([scoreAll(p), matchDocsFor(me)]);
  const matched = new Set(matches.map((d) => d.pids.find((x) => x !== me)!));
  return scored
    .filter((s) => want.has(s.other.pid) && s.other.status !== "red")
    .map((s) => ({
      pid: s.other.pid,
      name: s.other.name,
      status: s.other.status,
      tier: matched.has(s.other.pid) ? "match" : s.score >= 0.65 ? "strong" : s.score >= 0.4 ? "good" : "weak",
      score: Math.round(s.score * 100) / 100,
      reason: reasonCache.get(`person:${me}:${s.other.pid}`) ?? templatePersonReason(p, s),
    }));
}

export { savedTalkIds };
