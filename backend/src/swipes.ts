import { es, IDX, getDoc, searchAll } from "./elastic";
import type { SwipeDir, TargetType } from "./types";

export interface SwipeDoc {
  pid: string;
  target_type: TargetType;
  target_id: string;
  dir: SwipeDir;
  ts: string;
}

export const swipeId = (pid: string, type: TargetType, target: string) => `${pid}__${type}__${target}`;

export async function putSwipe(s: Omit<SwipeDoc, "ts">): Promise<SwipeDoc> {
  const doc: SwipeDoc = { ...s, ts: new Date().toISOString() };
  await es().index({ index: IDX.swipes, id: swipeId(s.pid, s.target_type, s.target_id), document: doc, refresh: true });
  return doc;
}

export async function getSwipe(pid: string, type: TargetType, target: string): Promise<SwipeDoc | null> {
  return getDoc<SwipeDoc>(IDX.swipes, swipeId(pid, type, target));
}

/** All of one person's swipes of a type, as target_id -> dir. */
export async function swipesOf(pid: string, type: TargetType): Promise<Map<string, SwipeDir>> {
  const docs = await searchAll<SwipeDoc>(
    IDX.swipes,
    { bool: { filter: [{ term: { pid } }, { term: { target_type: type } }] } },
    5000,
  );
  return new Map(docs.map((d) => [d.target_id, d.dir]));
}

/** Saved talk ids (right or up) per person, for everyone. Small at demo scale. */
export async function savedTalksByPerson(): Promise<Map<string, Set<string>>> {
  const docs = await searchAll<SwipeDoc>(
    IDX.swipes,
    { bool: { filter: [{ term: { target_type: "talk" } }, { terms: { dir: ["right", "up"] } }] } },
    10000,
  );
  const out = new Map<string, Set<string>>();
  for (const d of docs) {
    if (!out.has(d.pid)) out.set(d.pid, new Set());
    out.get(d.pid)!.add(d.target_id);
  }
  return out;
}

export async function savedTalkIds(pid: string): Promise<{ saved: string[]; must: Set<string> }> {
  const m = await swipesOf(pid, "talk");
  const saved = [...m.entries()].filter(([, d]) => d !== "left").map(([t]) => t);
  const must = new Set([...m.entries()].filter(([, d]) => d === "up").map(([t]) => t));
  return { saved, must };
}
