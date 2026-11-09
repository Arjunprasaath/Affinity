import OpenAI from "openai";
import { config } from "./config";
import { traced, llmDuration } from "./otel";

let client: OpenAI | null = null;
function openai(): OpenAI | null {
  if (!config.openai.apiKey) return null;
  if (!client) client = new OpenAI({ apiKey: config.openai.apiKey, timeout: 15000, maxRetries: 1 });
  return client;
}

/**
 * Ask the model for a JSON object. Returns null (never throws) when OpenAI isn't configured
 * or the call fails, so every caller has a template fallback.
 */
export async function chatJSON<T>(name: string, system: string, user: string): Promise<T | null> {
  const c = openai();
  if (!c) return null;
  return traced(`openai.${name}`, { "gen_ai.system": "openai", "gen_ai.request.model": config.openai.model }, async (span) => {
    const t0 = Date.now();
    try {
      const r = await c.chat.completions.create({
        model: config.openai.model,
        response_format: { type: "json_object" },
        temperature: 0.3,
        messages: [
          { role: "system", content: system },
          { role: "user", content: user },
        ],
      });
      span.setAttribute("gen_ai.usage.input_tokens", r.usage?.prompt_tokens ?? 0);
      span.setAttribute("gen_ai.usage.output_tokens", r.usage?.completion_tokens ?? 0);
      const text = r.choices[0]?.message?.content ?? "";
      return JSON.parse(text) as T;
    } catch (err) {
      span.setAttribute("orbit.llm.fallback", true);
      span.recordException(err as Error);
      return null;
    } finally {
      llmDuration.record(Date.now() - t0, { op: name });
    }
  });
}

/** Simple in-memory cache for generated reasons. */
export const reasonCache = new Map<string, string>();
