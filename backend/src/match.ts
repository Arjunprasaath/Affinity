// backend/src/match.ts
// STUB: returns the sample from the API contract. Arjun replaces the body.
// Skip this file if Arjun has already pushed his own match.ts.

export interface MatchResult {
  pid: string;
  score: number;
  tier: "strong" | "good" | "weak";
  reason: string;
  shared_topics: string[];
}

export async function match(me: string, others: string[]): Promise<MatchResult[]> {
  return others.map((pid, i) => {
    const score = Math.max(0.2, 0.82 - i * 0.25);
    return {
      pid,
      score,
      tier: score >= 0.65 ? "strong" : score >= 0.4 ? "good" : "weak",
      reason: "Priya is looking for GPU autoscaling contributors, which you've done.",
      shared_topics: ["kubernetes", "gpu"],
    };
  });
}
