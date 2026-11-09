/**
 * End-to-end check of the whole demo journey against a running server.
 *   BASE_URL=http://localhost:8080 npm run smoke
 *   SMOKE_GITHUB=<username> npm run smoke   # also exercise GitHub ingestion
 */
const BASE = process.env.BASE_URL ?? "http://localhost:8080";

async function call<T = any>(method: string, path: string, body?: unknown): Promise<T> {
  const t0 = Date.now();
  const res = await fetch(BASE + path, {
    method,
    headers: body ? { "content-type": "application/json" } : undefined,
    body: body ? JSON.stringify(body) : undefined,
  });
  const json = await res.json().catch(() => ({}));
  console.log(`${res.ok ? "✓" : "✗"} ${method} ${path} → ${res.status} (${Date.now() - t0}ms)`);
  if (!res.ok) throw new Error(`${method} ${path} failed: ${JSON.stringify(json)}`);
  return json as T;
}

async function main() {
  const health = await call("GET", "/healthz");
  console.log("  config:", health.config);

  const me = await call("POST", "/profiles", {
    name: "Demo User",
    role: "ML Engineer",
    company: "Smoke Test Inc",
    github: process.env.SMOKE_GITHUB,
    working_on: "Serving LLMs on Kubernetes with GPU autoscaling",
    looking_for: "Learn multi-cluster networking and find people running model serving in production",
    offering: "GPU autoscaling and KServe deployment experience; happy to contribute to open source autoscalers",
    here_for: ["learning", "finding_contributors"],
  });
  console.log(`  profile ${me.pid}: topics=${me.topics.join(", ")}`);

  const talks = await call<any[]>("GET", `/talks/recommended?pid=${me.pid}&limit=5`);
  talks.forEach((t) => console.log(`  talk ${t.tid} ${t.title} — ${t.reason}`));
  await call("POST", "/swipes", { pid: me.pid, target_type: "talk", target_id: talks[0].tid, dir: "up" });
  await call("POST", "/swipes", { pid: me.pid, target_type: "talk", target_id: talks[1].tid, dir: "right" });
  await call("POST", "/swipes", { pid: me.pid, target_type: "talk", target_id: talks[2].tid, dir: "left" });
  const more = await call<any[]>("GET", `/talks/recommended?pid=${me.pid}&limit=3`);
  console.log(`  next deck: ${more.map((t) => t.tid).join(", ")}`);
  await call("POST", "/swipes", { pid: me.pid, target_type: "talk", target_id: more[0].tid, dir: "right" });

  const sched = await call("GET", `/schedule/${me.pid}`);
  console.log(`  schedule: ${sched.items.length} talks, ${sched.free.length} free blocks`);

  const people = await call<any[]>("GET", `/people/recommended?pid=${me.pid}&limit=5`);
  people.forEach((p) => console.log(`  person ${p.pid} ${p.score} — ${p.reason}`));

  let match: any = null;
  for (const p of people) {
    const r = await call("POST", "/swipes", { pid: me.pid, target_type: "person", target_id: p.pid, dir: "right" });
    if (r.match) {
      match = r.match;
      break;
    }
  }
  if (!match) throw new Error("no persona matched back; lower PERSONA_AUTOLIKE_THRESHOLD");
  console.log(`  matched with ${match.name}: ${match.reason}`);

  const matches = await call<any[]>("GET", `/matches/${me.pid}`);
  console.log(`  matches: ${matches.map((m) => m.name).join(", ")}`);

  const meet = await call("GET", `/meet?a=${me.pid}&b=${match.pid}`);
  console.log(`  shared talks: ${meet.shared_talks.map((t: any) => t.title).join(" | ") || "none"}`);
  console.log(`  free overlaps: ${meet.free_overlaps.length}, their next: ${JSON.stringify(meet.their_next)}`);
  meet.suggestions.forEach((s: any) => console.log(`  suggestion: ${s.label} @ ${s.place}`));

  const s = meet.suggestions[0];
  const m = await call("POST", "/meetups", { a: me.pid, b: match.pid, place: s.place, start: s.start, end: s.end, label: s.label });
  await call("PATCH", `/meetups/${m.id}`, { status: "accepted", pid: match.pid });
  const sched2 = await call("GET", `/schedule/${me.pid}`);
  console.log(`  schedule now has ${sched2.meetups.length} accepted meetup(s)`);

  const radar = await call<any[]>("POST", "/radar/match", { me: me.pid, others: [match.pid, people[people.length - 1].pid, "p_grace"] });
  radar.forEach((r) => console.log(`  radar ${r.name}: ${r.tier} (${r.score})`));

  // Negative checks
  const forbidden = await fetch(`${BASE}/meet?a=${me.pid}&b=p_sofia`);
  console.log(`${forbidden.status === 403 ? "✓" : "✗"} /meet for non-match → ${forbidden.status} (expected 403)`);
  const missing = await fetch(`${BASE}/profiles/p_doesnotexist`);
  console.log(`${missing.status === 404 ? "✓" : "✗"} unknown profile → ${missing.status} (expected 404)`);

  console.log("\nSmoke test passed.");
}

main().catch((e) => {
  console.error("\nSmoke test FAILED:", e.message);
  process.exit(1);
});
