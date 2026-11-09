/**
 * Creates the Elastic indices (dropping existing ones) and loads talks, personas and the personas' saved talks.
 *   npm run seed            # recreate everything
 *   npm run seed -- --keep  # only create missing indices, then upsert data
 */
import "../src/config";
import { es, IDX, ensureIndices } from "../src/elastic";
import { loadPersonas, loadTalks } from "../src/data";
import { swipeId } from "../src/swipes";
import type { Profile } from "../src/types";

async function bulk(index: string, docs: { id: string; doc: object }[], chunk = 16) {
  for (let i = 0; i < docs.length; i += chunk) {
    const ops = docs.slice(i, i + chunk).flatMap(({ id, doc }) => [{ index: { _index: index, _id: id } }, doc]);
    const r = await es().bulk({ operations: ops, refresh: true });
    if (r.errors) {
      const bad = r.items.find((it) => it.index?.error);
      throw new Error(`bulk into ${index} failed: ${JSON.stringify(bad?.index?.error)}`);
    }
    process.stdout.write(`  ${index}: ${Math.min(i + chunk, docs.length)}/${docs.length}\r`);
  }
  process.stdout.write("\n");
}

async function main() {
  const keep = process.argv.includes("--keep");
  const t0 = Date.now();
  console.log(keep ? "Ensuring indices exist…" : "Recreating indices…");
  await ensureIndices(!keep);

  const talks = loadTalks();
  console.log(`Indexing ${talks.length} talks (semantic_text embeddings are computed by Elastic; first run can take a minute)…`);
  await bulk(
    IDX.talks,
    talks.map((t) => ({ id: t.tid, doc: { ...t, content: `${t.title}. ${t.abstract} Speakers: ${t.speakers.join(", ")}` } })),
  );

  const personas = loadPersonas();
  console.log(`Indexing ${personas.length} fictional personas…`);
  await bulk(
    IDX.profiles,
    personas.map(({ saved, ...p }) => {
      const doc: Profile = {
        ...p,
        summary: `${p.role} at ${p.company}, working on ${p.working_on.charAt(0).toLowerCase()}${p.working_on.slice(1)}.`,
        evidence: [],
        hide_next_room: false,
        is_persona: true,
        created_at: new Date().toISOString(),
      };
      return { id: p.pid, doc };
    }),
  );

  const known = new Set(talks.map((t) => t.tid));
  const swipes = personas.flatMap((p) =>
    p.saved.filter((tid) => known.has(tid)).map((tid) => ({
      id: swipeId(p.pid, "talk", tid),
      doc: { pid: p.pid, target_type: "talk", target_id: tid, dir: "right", ts: new Date().toISOString() },
    })),
  );
  console.log(`Indexing ${swipes.length} persona talk saves…`);
  await bulk(IDX.swipes, swipes, 200);

  console.log(`Done in ${((Date.now() - t0) / 1000).toFixed(1)}s. Indices: ${Object.values(IDX).join(", ")}`);
}

main().catch((err) => {
  console.error("Seed failed:", err?.meta?.body?.error ?? err);
  process.exit(1);
});
