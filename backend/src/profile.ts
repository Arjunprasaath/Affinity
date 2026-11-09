import { randomBytes } from "node:crypto";
import { es, IDX, getDoc } from "./elastic";
import { fetchGithub, type GithubSignals } from "./github";
import { chatJSON } from "./llm";
import { traced } from "./otel";
import { badRequest, notFound } from "./errors";
import type { Evidence, Profile, Status } from "./types";

/** Topic vocabulary used for the heuristic fallback and to steer the LLM toward consistent tags. */
export const TOPIC_VOCAB: Record<string, RegExp> = {
  kubernetes: /\bkubernetes\b|\bk8s\b/i,
  ebpf: /\bebpf\b|\bbpf\b|cilium|falco|tetragon/i,
  networking: /network|ingress|gateway api|\bcni\b|dns/i,
  "service-mesh": /service mesh|istio|linkerd|envoy|sidecar/i,
  security: /secur|threat|vulnerab|cve|zero.?trust|spiffe/i,
  "supply-chain": /supply.?chain|sigstore|cosign|slsa|sbom|signing|provenance/i,
  policy: /policy|kyverno|\bopa\b|gatekeeper|admission/i,
  observability: /observab|monitor|prometheus|grafana|dashboard|logging|tracing/i,
  opentelemetry: /opentelemetry|\botel\b/i,
  performance: /performance|latency|profil|benchmark/i,
  sre: /\bsre\b|reliability|on.?call|\bslo\b|error budget/i,
  "incident-response": /incident|postmortem|root cause|chaos/i,
  "platform-engineering": /platform eng|internal developer platform|\bidp\b|platform team|paved road|golden path/i,
  "developer-experience": /developer experience|\bdevex\b|backstage|developer portal/i,
  gitops: /gitops|argo ?cd|flux|argo rollouts/i,
  "multi-cluster": /multi.?cluster|fleet|multi.?region|multi.?tenan/i,
  llm: /\bllms?\b|large language|language models?|\bgpt\b|transformer/i,
  pretraining: /pre-?train/i,
  "fine-tuning": /fine-?tun|\blora\b|instruction[- ]tun|\brlhf\b|\bsft\b/i,
  rag: /\brag\b|retrieval[- ]augmented/i,
  evaluation: /\bevals?\b|evaluat|benchmark/i,
  "ai-ml": /\bai\b|\bml\b|machine learning|genai|mlops/i,
  "llm-serving": /serving|inference|kserve|vllm|triton/i,
  gpu: /\bgpu|cuda|nvidia/i,
  autoscaling: /autoscal|\bkeda\b|\bhpa\b|karpenter|scale.?to.?zero/i,
  scheduling: /schedul|kueue|quota|volcano/i,
  agents: /\bagent(s|ic)?\b/i,
  search: /search|retrieval|\brag\b|vector|elasticsearch/i,
  cost: /\bcost|finops|spend|budget/i,
  storage: /storage|\bcsi\b|volume|stateful|backup/i,
  databases: /database|postgres|mysql|redis|cassandra/i,
  edge: /\bedge\b|iot|k3s/i,
  wasm: /wasm|webassembly/i,
  serverless: /serverless|knative|faas/i,
  operators: /operator|controller|\bcrd\b|kubebuilder/i,
  "infrastructure-as-code": /terraform|crossplane|pulumi|infrastructure as code|\biac\b/i,
  "open-source": /open.?source|maintainer|contribut|\bcncf\b/i,
  community: /communit|mentor|meetup|inclusi|divers/i,
  accessibility: /accessib|a11y|screen reader|inclusive design/i,
  career: /career|job|hiring|interview|apprentic/i,
  leadership: /manag|leadership|\blead\b|team growth/i,
  go: /\bgolang\b|\bgo\b(?! to)/i,
  rust: /\brust\b/i,
  python: /\bpython\b/i,
};

export interface ProfileInput {
  pid?: string;
  name?: string;
  role?: string;
  company?: string;
  pronouns?: string;
  github?: string;
  linkedin?: string;
  working_on?: string;
  looking_for?: string;
  offering?: string;
  here_for?: string[];
  topics?: string[];
  status?: Status;
  hide_next_room?: boolean;
}

function heuristicTopics(selfText: string, gh: GithubSignals | null): { topics: string[]; evidence: Evidence[] } {
  const score = new Map<string, number>();
  const evidence: Evidence[] = [];
  const bump = (topic: string, n: number, source: string) => {
    score.set(topic, (score.get(topic) ?? 0) + n);
    if (evidence.filter((e) => e.topic === topic).length < 2) evidence.push({ topic, source });
  };
  for (const [topic, re] of Object.entries(TOPIC_VOCAB)) {
    if (re.test(selfText)) bump(topic, 2, "self");
    for (const r of gh?.repos ?? []) {
      const t = [r.name, r.description, r.language, ...r.topics].filter(Boolean).join(" ");
      if (re.test(t)) bump(topic, 1, `github:${gh!.login}/${r.name}`);
    }
    for (const r of gh?.starred ?? []) {
      const t = [r.name, r.description, ...r.topics].filter(Boolean).join(" ");
      if (re.test(t)) bump(topic, 0.5, `github-star:${r.name}`);
    }
  }
  const topics = [...score.entries()]
    .filter(([, n]) => n >= 2)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 8)
    .map(([t]) => t);
  return { topics, evidence: evidence.filter((e) => topics.includes(e.topic)) };
}

async function extract(input: ProfileInput, gh: GithubSignals | null) {
  const selfText = [input.role, input.working_on, input.looking_for, input.offering].filter(Boolean).join(". ");
  const fallback = heuristicTopics(selfText, gh);

  const llm = await chatJSON<{ topics: string[]; summary: string; evidence: Evidence[] }>(
    "extract_profile",
    `You build conference-matching profiles for a cloud native conference (KubeCon).
Return JSON: {"topics": string[], "summary": string, "evidence": [{"topic": string, "source": string}]}.
- topics: at most 8, lowercase kebab-case. Prefer these when they fit: ${Object.keys(TOPIC_VOCAB).join(", ")}.
- Only include a topic if the person's own words mention it, or at least two GitHub signals support it. Don't guess from one starred repo.
- Put the topics from the person's own words first, using the most specific tag (e.g. "pretraining", "fine-tuning", "llm" rather than "ai-ml").
- evidence: one entry per topic; source is "self" or "github:<repo>" or "github-star:<repo>".
- summary: one sentence, third person, under 25 words, about what they build and care about.`,
    JSON.stringify({
      role: input.role,
      company: input.company,
      working_on: input.working_on,
      looking_for: input.looking_for,
      offering: input.offering,
      github: gh && {
        bio: gh.bio,
        repos: gh.repos.map((r) => ({ name: r.name, description: r.description, language: r.language, topics: r.topics })),
        starred: gh.starred.slice(0, 20).map((r) => ({ name: r.name, description: r.description, topics: r.topics })),
      },
    }),
  );

  const topics = (llm?.topics?.length ? llm.topics : fallback.topics)
    .map((t) => t.toLowerCase().trim().replace(/\s+/g, "-"))
    .filter(Boolean)
    .slice(0, 8);
  const summary =
    llm?.summary ||
    [input.role, input.company && `at ${input.company}`].filter(Boolean).join(" ") +
      (input.working_on ? `, working on ${input.working_on.replace(/\.$/, "")}.` : ".");
  return { topics, summary, evidence: llm?.evidence?.length ? llm.evidence : fallback.evidence };
}

/**
 * The topics a person actually said they care about. Tags that only came from GitHub
 * (e.g. a starred repo) are left out when the person stated interests themselves,
 * so "I like LLMs, pretraining, fine-tuning" means only those.
 */
export function interestTopics(p: Profile): string[] {
  const self = new Set((p.evidence ?? []).filter((e) => e.source === "self").map((e) => e.topic));
  const stated = p.topics.filter((t) => self.has(t));
  return stated.length ? stated : p.topics;
}

export function newPid(): string {
  return "p_" + randomBytes(4).toString("hex");
}

export async function createProfile(input: ProfileInput): Promise<Profile> {
  if (!input.name?.trim()) throw badRequest("name is required");
  if (!input.working_on?.trim() && !input.looking_for?.trim() && !input.github?.trim()) {
    throw badRequest("give at least one of working_on, looking_for or github");
  }
  return traced("profile.build", { "orbit.has_github": Boolean(input.github) }, async (span) => {
    const gh = input.github ? await fetchGithub(input.github) : null;
    span.setAttribute("orbit.github_found", Boolean(gh));
    const { topics, summary, evidence } = await extract(input, gh);

    const workingOn = input.working_on?.trim() || gh?.bio || summary;
    const profile: Profile = {
      pid: input.pid?.trim() || newPid(),
      name: input.name!.trim(),
      role: input.role?.trim() || undefined,
      company: input.company?.trim() || gh?.company?.replace(/^@/, "") || undefined,
      pronouns: input.pronouns?.trim() || undefined,
      github: gh?.login ?? input.github?.trim() ?? undefined,
      linkedin: input.linkedin?.trim() || undefined,
      working_on: workingOn,
      // semantic_text fields must not be empty; fall back to related text
      looking_for: input.looking_for?.trim() || `People working on ${topics.slice(0, 3).join(", ") || workingOn}`,
      offering: input.offering?.trim() || `Experience with ${workingOn}`,
      here_for: input.here_for ?? [],
      topics: [...new Set([...(input.topics ?? []), ...topics])].slice(0, 10),
      summary,
      evidence,
      status: input.status ?? "green",
      hide_next_room: input.hide_next_room ?? false,
      is_persona: false,
      created_at: new Date().toISOString(),
    };
    await es().index({ index: IDX.profiles, id: profile.pid, document: profile, refresh: true });
    span.setAttribute("orbit.topics", profile.topics.length);
    return profile;
  });
}

export async function getProfile(pid: string): Promise<Profile> {
  const p = await getDoc<Profile>(IDX.profiles, pid);
  if (!p) throw notFound(`profile ${pid}`);
  return p;
}

const EDITABLE = ["name", "linkedin", "role", "company", "pronouns", "working_on", "looking_for", "offering", "here_for", "topics", "status", "hide_next_room"] as const;

export async function patchProfile(pid: string, patch: Partial<Profile>): Promise<Profile> {
  await getProfile(pid);
  const doc: Record<string, unknown> = {};
  for (const k of EDITABLE) if (patch[k] !== undefined) doc[k] = patch[k];
  if (doc.status && !["green", "yellow", "red"].includes(doc.status as string)) throw badRequest("status must be green, yellow or red");
  for (const k of ["working_on", "looking_for", "offering"]) {
    if (k in doc && !String(doc[k]).trim()) throw badRequest(`${k} cannot be empty`);
  }
  if (Object.keys(doc).length) await es().update({ index: IDX.profiles, id: pid, doc, refresh: true });
  return getProfile(pid);
}

export async function getProfiles(pids: string[]): Promise<Map<string, Profile>> {
  const out = new Map<string, Profile>();
  if (!pids.length) return out;
  const r = await es().mget<Profile>({ index: IDX.profiles, ids: [...new Set(pids)] });
  for (const d of r.docs) if ("found" in d && d.found && d._source) out.set(d._id, d._source);
  return out;
}

/** Public subset safe to show to anyone (no evidence internals). */
export function publicProfile(p: Profile) {
  const { evidence, is_persona, created_at, ...rest } = p;
  return rest;
}
