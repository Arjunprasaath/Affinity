import { config } from "./config";
import { traced } from "./otel";

export interface GithubSignals {
  login: string;
  bio?: string;
  company?: string;
  repos: { name: string; description?: string; language?: string; topics: string[] }[];
  starred: { name: string; description?: string; topics: string[] }[];
}

async function gh<T>(path: string): Promise<T> {
  const res = await fetch(`https://api.github.com${path}`, {
    headers: {
      Accept: "application/vnd.github+json",
      "User-Agent": "orbit-hackathon-app",
      ...(config.githubToken ? { Authorization: `Bearer ${config.githubToken}` } : {}),
    },
    signal: AbortSignal.timeout(5000),
  });
  if (!res.ok) throw new Error(`GitHub ${path} -> ${res.status}`);
  return (await res.json()) as T;
}

/** Fetch public signals for a GitHub user. Returns null if the user can't be fetched. */
export async function fetchGithub(username: string): Promise<GithubSignals | null> {
  const login = username.replace(/^@/, "").replace(/^https?:\/\/github\.com\//, "").split("/")[0].trim();
  if (!login) return null;
  return traced("github.fetch", { "github.login": login }, async (span) => {
    const [user, repos, starred] = await Promise.allSettled([
      gh<any>(`/users/${login}`),
      gh<any[]>(`/users/${login}/repos?sort=pushed&per_page=10&type=owner`),
      gh<any[]>(`/users/${login}/starred?per_page=30`),
    ]);
    if (user.status !== "fulfilled") {
      span.setAttribute("github.found", false);
      return null;
    }
    const out: GithubSignals = {
      login,
      bio: user.value.bio ?? undefined,
      company: user.value.company ?? undefined,
      repos:
        repos.status === "fulfilled"
          ? repos.value
              .filter((r) => !r.fork)
              .map((r) => ({ name: r.name, description: r.description ?? undefined, language: r.language ?? undefined, topics: r.topics ?? [] }))
          : [],
      starred:
        starred.status === "fulfilled"
          ? starred.value.map((r) => ({ name: r.full_name, description: r.description ?? undefined, topics: r.topics ?? [] }))
          : [],
    };
    span.setAttribute("github.repos", out.repos.length);
    span.setAttribute("github.starred", out.starred.length);
    return out;
  });
}
