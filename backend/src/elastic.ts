import { Client } from "@elastic/elasticsearch";
import { config } from "./config";

function makeClient(): Client {
  const { url, cloudId, apiKey, username, password } = config.elastic;
  if (!url && !cloudId) {
    throw new Error("Elasticsearch is not configured: set ELASTIC_URL (or ELASTIC_CLOUD_ID) and ELASTIC_API_KEY");
  }
  return new Client({
    ...(cloudId ? { cloud: { id: cloudId } } : { node: url }),
    auth: apiKey ? { apiKey } : { username: username ?? "elastic", password: password ?? "" },
    requestTimeout: 60000,
  });
}

let _client: Client | null = null;
export function es(): Client {
  if (!_client) _client = makeClient();
  return _client;
}

const p = config.elastic.indexPrefix;
export const IDX = {
  profiles: `${p}-profiles`,
  talks: `${p}-talks`,
  swipes: `${p}-swipes`,
  matches: `${p}-matches`,
  meetups: `${p}-meetups`,
};

const semantic = () =>
  config.elastic.inferenceId && config.elastic.inferenceId !== "default"
    ? { type: "semantic_text" as const, inference_id: config.elastic.inferenceId }
    : { type: "semantic_text" as const };

export const MAPPINGS: Record<keyof typeof IDX, Record<string, unknown>> = {
  profiles: {
    pid: { type: "keyword" },
    name: { type: "text", fields: { raw: { type: "keyword" } } },
    role: { type: "keyword" },
    company: { type: "keyword" },
    pronouns: { type: "keyword" },
    github: { type: "keyword" },
    status: { type: "keyword" },
    here_for: { type: "keyword" },
    topics: { type: "keyword" },
    summary: { type: "text" },
    working_on: semantic(),
    looking_for: semantic(),
    offering: semantic(),
    evidence: { type: "object", enabled: false },
    hide_next_room: { type: "boolean" },
    is_persona: { type: "boolean" },
    created_at: { type: "date" },
  },
  talks: {
    tid: { type: "keyword" },
    title: { type: "text" },
    abstract: { type: "text" },
    speakers: { type: "text" },
    room: { type: "keyword" },
    start: { type: "date" },
    end: { type: "date" },
    level: { type: "keyword" },
    track: { type: "keyword" },
    topics: { type: "keyword" },
    content: semantic(),
  },
  swipes: {
    pid: { type: "keyword" },
    target_type: { type: "keyword" },
    target_id: { type: "keyword" },
    dir: { type: "keyword" },
    ts: { type: "date" },
  },
  matches: {
    pids: { type: "keyword" },
    reason: { type: "text" },
    matched_at: { type: "date" },
  },
  meetups: {
    id: { type: "keyword" },
    a: { type: "keyword" },
    b: { type: "keyword" },
    pids: { type: "keyword" },
    place: { type: "keyword" },
    label: { type: "text" },
    start: { type: "date" },
    end: { type: "date" },
    status: { type: "keyword" },
    created_at: { type: "date" },
  },
};

/** Create any missing indices. With recreate=true, deletes and recreates them (used by the seed script). */
export async function ensureIndices(recreate = false): Promise<void> {
  for (const key of Object.keys(IDX) as (keyof typeof IDX)[]) {
    const index = IDX[key];
    const exists = await es().indices.exists({ index });
    if (exists && recreate) await es().indices.delete({ index });
    if (!exists || recreate) {
      await es().indices.create({ index, mappings: { properties: MAPPINGS[key] as any } });
    }
  }
}

/** Get a document's _source, or null if it doesn't exist. */
export async function getDoc<T>(index: string, id: string): Promise<T | null> {
  try {
    const r = await es().get<T>({ index, id });
    return (r._source as T) ?? null;
  } catch (e: any) {
    if (e?.meta?.statusCode === 404) return null;
    throw e;
  }
}

export async function searchAll<T>(index: string, query: Record<string, unknown>, size = 1000): Promise<T[]> {
  const r = await es().search<T>({ index, query: query as any, size });
  return r.hits.hits.map((h) => h._source as T);
}
