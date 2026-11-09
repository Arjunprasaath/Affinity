import { es, IDX, getDoc, searchAll } from "./elastic";

export interface MatchDoc {
  pids: [string, string];
  reason: string;
  matched_at: string;
}

export const matchId = (a: string, b: string) => [a, b].sort().join("__");

export async function getMatchDoc(a: string, b: string): Promise<MatchDoc | null> {
  return getDoc<MatchDoc>(IDX.matches, matchId(a, b));
}

export async function putMatch(a: string, b: string, reason: string): Promise<MatchDoc> {
  const doc: MatchDoc = { pids: [a, b].sort() as [string, string], reason, matched_at: new Date().toISOString() };
  await es().index({ index: IDX.matches, id: matchId(a, b), document: doc, refresh: true });
  return doc;
}

export async function matchDocsFor(pid: string): Promise<MatchDoc[]> {
  return searchAll<MatchDoc>(IDX.matches, { term: { pids: pid } }, 1000);
}

export async function matchedPids(pid: string): Promise<string[]> {
  return (await matchDocsFor(pid)).map((m) => m.pids.find((x) => x !== pid)!).filter(Boolean);
}
