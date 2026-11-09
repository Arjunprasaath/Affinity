// backend/src/profile.ts
// POST/GET/PATCH /profiles: GitHub fetch -> OpenAI structured extraction -> Elastic.
// Works with no keys at all (in-memory store, empty topics), so it doubles as the stub.
import { randomBytes } from "node:crypto";
import OpenAI from "openai";
import { Client } from "@elastic/elasticsearch";
import { withSpan } from "./otel";

const INDEX = "profiles";
const MODEL = process.env.OPENAI_MODEL || "gpt-4o-mini"; // any small, fast model

export interface ProfileInput {
  pid?: string;
  name: string;
  role?: string;
  company?: string;
  pronouns?: string;
  github?: string;
  working_on?: string;
  looking_for?: string;
  offering?: string;
  here_for?: string[];
  status?: "green" | "yellow" | "red";
}

export interface Profile extends ProfileInput {
  pid: string;
  topics: string[];
  summary: string;
  evidence: { topic: string; source: string }[];
  is_persona: boolean;
}

// In-memory store: fallback while Elastic isn't ready, read cache afterwards.
const store = new Map<string, Profile>();

// Swap this for the client exported from Arjun's elastic.ts once it exists.
const es = process.env.ELASTIC_URL
  ? new Client({
      node: process.env.ELASTIC_URL,
      auth: { apiKey: process.env.ELASTIC_API_KEY || "" },
    })
  : null;

const openai = process.env.OPENAI_API_KEY ? new OpenAI({ timeout: 15_000 }) : null;

// ---------- GitHub ----------

async function gh(path: string): Promise<any | null> {
  const res = await fetch(`https://api.github.com${path}`, {
    headers: {
      "User-Agent": "orbit-hackathon",
      Accept: "application/vnd.github+json",
      ...(process.env.GITHUB_TOKEN
        ? { Authorization: `Bearer ${process.env.GITHUB_TOKEN}` }
        : {}),
    },
    signal: AbortSignal.timeout(5000),
  });
  return res.ok ? res.json() : null;
}

// Returns a small, trimmed digest. The raw GitHub payload is never stored or logged.
async function fetchGithubDigest(username: string): Promise<string | null> {
  const u = encodeURIComponent(username);
  const settled = await Promise.allSettled([
    gh(`/users/${u}`),
    gh(`/users/${u}/repos?sort=pushed&per_page=10`),
    gh(`/users/${u}/starred?per_page=30`),
  ]);
  const [user, repos, starred] = settled.map((r) =>
    r.status === "fulfilled" ? r.value : null
  );
  if (!user && !repos && !starred) return null;

  const repoLine = (r: any) =>
    `${r.full_name}: ${r.description ?? ""} [${r.language ?? ""}] topics=${(r.topics ?? []).join(",")}`;

  return [
    user ? `BIO: ${user.bio ?? ""} | company: ${user.company ?? ""}` : "",
    Array.isArray(repos) ? `OWN REPOS:\n${repos.map(repoLine).join("\n")}` : "",
    Array.isArray(starred) ? `STARRED:\n${starred.map(repoLine).join("\n")}` : "",
  ]
    .filter(Boolean)
    .join("\n\n");
}

// ---------- OpenAI extraction ----------

const EXTRACTION_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["topics", "summary", "evidence"],
  properties: {
    topics: { type: "array", items: { type: "string" } },
    summary: { type: "string" },
    evidence: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["topic", "source"],
        properties: { topic: { type: "string" }, source: { type: "string" } },
      },
    },
  },
} as const;

const SYSTEM_PROMPT = `You build a conference attendee's technical profile.
Return:
- topics: at most 8 technical topics, lowercase kebab-case (e.g. "llm-serving").
  Only include a topic if it has at least 2 independent signals in the GitHub data,
  OR it appears in the person's own text. The person's own text outranks GitHub.
- summary: one sentence describing what this person works on.
- evidence: for each topic, one source, formatted "github:owner/repo" or "self" for their own text.
Do not invent anything that is not supported by the input.`;

const kebab = (s: string) =>
  s.toLowerCase().trim().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");

async function extract(input: ProfileInput, githubDigest: string | null) {
  const empty = {
    topics: [] as string[],
    summary: input.working_on ?? "",
    evidence: [] as { topic: string; source: string }[],
  };
  if (!openai) return empty;

  const userText = [
    `Name: ${input.name}`,
    `Role: ${input.role ?? ""} at ${input.company ?? ""}`,
    `Working on: ${input.working_on ?? ""}`,
    `Looking for: ${input.looking_for ?? ""}`,
    `Offering: ${input.offering ?? ""}`,
    githubDigest ? `\nGITHUB DATA:\n${githubDigest}` : "\n(no GitHub data)",
  ].join("\n");

  try {
    const res = await openai.chat.completions.create({
      model: MODEL,
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: userText },
      ],
      response_format: {
        type: "json_schema",
        json_schema: { name: "profile_extraction", strict: true, schema: EXTRACTION_SCHEMA },
      },
    });
    const parsed = JSON.parse(res.choices[0].message.content ?? "{}");
    const topics = [...new Set((parsed.topics ?? []).map(kebab).filter(Boolean))].slice(0, 8) as string[];
    return {
      topics,
      summary: parsed.summary || empty.summary,
      evidence: (parsed.evidence ?? []).map((e: any) => ({
        topic: kebab(e.topic),
        source: e.source,
      })),
    };
  } catch {
    return empty; // onboarding must still succeed if the LLM call fails
  }
}

// ---------- Storage ----------

async function save(profile: Profile): Promise<void> {
  store.set(profile.pid, profile);
  if (!es) return;
  try {
    // refresh: true so /match can see this person immediately
    await es.index({ index: INDEX, id: profile.pid, document: profile, refresh: true });
  } catch (err) {
    console.error("elastic index failed, kept in memory:", (err as Error).message);
  }
}

// ---------- Handlers used by server.ts ----------

export async function createProfile(input: ProfileInput): Promise<Profile> {
  const pid = input.pid || `p_${randomBytes(4).toString("hex").slice(0, 5)}`;

  const digest = input.github
    ? await withSpan("github.fetch", () => fetchGithubDigest(input.github!)).catch(() => null)
    : null;

  const extracted = await withSpan("openai.extract", () => extract(input, digest));

  const profile: Profile = {
    ...input,
    pid,
    here_for: input.here_for ?? [],
    status: input.status ?? "green",
    ...extracted,
    is_persona: false,
  };
  await save(profile);
  return profile;
}

export async function getProfile(pid: string): Promise<Profile | null> {
  const cached = store.get(pid);
  if (cached) return cached;
  if (!es) return null;
  try {
    const res = await es.get<Profile>({ index: INDEX, id: pid });
    if (res._source) store.set(pid, res._source);
    return res._source ?? null;
  } catch {
    return null;
  }
}

const PATCHABLE = ["topics", "status", "working_on", "looking_for", "offering", "here_for"] as const;

export async function patchProfile(
  pid: string,
  patch: Partial<Profile>
): Promise<Profile | null> {
  const existing = await getProfile(pid);
  if (!existing) return null;

  const updated: Profile = { ...existing };
  for (const key of PATCHABLE) {
    if (patch[key] !== undefined) (updated as any)[key] = patch[key];
  }
  if (patch.topics) updated.topics = patch.topics.map(kebab).filter(Boolean).slice(0, 8);

  await save(updated); // full re-index: safest with semantic_text fields
  return updated;
}
