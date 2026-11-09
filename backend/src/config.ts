import path from "node:path";
import dotenv from "dotenv";

// Load env from the repo root first, then backend/.env (backend wins). Values are never logged.
dotenv.config({ path: path.resolve(__dirname, "../../.env"), quiet: true });
dotenv.config({ path: path.resolve(__dirname, "../.env"), override: true, quiet: true });

function first(...names: string[]): string | undefined {
  for (const n of names) {
    const v = process.env[n];
    if (v && v.trim()) return v.trim();
  }
  return undefined;
}

export const config = {
  port: Number(process.env.PORT ?? 8080),
  host: process.env.HOST ?? "0.0.0.0",

  elastic: {
    url: first("ELASTIC_URL", "ELASTICSEARCH_URL", "ES_URL", "ELASTIC_ENDPOINT", "ELASTICSEARCH_ENDPOINT"),
    cloudId: first("ELASTIC_CLOUD_ID", "ELASTICSEARCH_CLOUD_ID", "ES_CLOUD_ID"),
    apiKey: first("ELASTIC_API_KEY", "ELASTICSEARCH_API_KEY", "ES_API_KEY"),
    username: first("ELASTIC_USERNAME", "ELASTICSEARCH_USERNAME"),
    password: first("ELASTIC_PASSWORD", "ELASTICSEARCH_PASSWORD"),
    indexPrefix: process.env.INDEX_PREFIX ?? "orbit",
    // Inference endpoint for semantic_text embeddings (Jina via Elastic Inference Service by default).
    // Set ELASTIC_INFERENCE_ID=default to use the cluster's default instead.
    inferenceId: first("ELASTIC_INFERENCE_ID") ?? ".jina-embeddings-v5-text-small",
  },

  openai: {
    apiKey: first("OPENAI_API_KEY", "OPENAI_API", "OPENAI_KEY"),
    model: process.env.OPENAI_MODEL ?? "gpt-4o-mini",
  },

  githubToken: first("GITHUB_TOKEN", "GH_TOKEN"),

  // Demo knobs
  demoNow: process.env.DEMO_NOW, // e.g. 2026-11-10T14:50:00-07:00 to pretend it's during the conference
  personaAutolikeThreshold: Number(process.env.PERSONA_AUTOLIKE_THRESHOLD ?? 0.45),
  dataDir: path.resolve(__dirname, "../../data"),
};

export function nowMs(): number {
  return config.demoNow ? Date.parse(config.demoNow) : Date.now();
}

export function configSummary() {
  return {
    elastic: Boolean((config.elastic.url || config.elastic.cloudId) && (config.elastic.apiKey || config.elastic.password)),
    openai: Boolean(config.openai.apiKey),
    github_token: Boolean(config.githubToken),
    otel: Boolean(process.env.OTEL_EXPORTER_OTLP_ENDPOINT || process.env.DASH0_ENDPOINT),
    demo_now: config.demoNow ?? null,
  };
}
