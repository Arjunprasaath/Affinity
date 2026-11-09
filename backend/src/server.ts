// backend/src/server.ts
// Entry point: starts Fastify and maps each URL to its handler.
// "./otel" MUST stay the first import so tracing hooks load before http/fastify.
import "./otel";
import Fastify from "fastify";
import cors from "@fastify/cors";
import { createProfile, getProfile, patchProfile } from "./profile";
import { match } from "./match"; // Arjun's file
import { sharedTalks } from "./talks"; // Arjun's file

const app = Fastify({ logger: true });
app.register(cors, { origin: true });

app.get("/healthz", async () => ({ ok: true }));

// ---- Profiles (teammate C) ----
app.post("/profiles", async (req, reply) => {
  const body = (req.body ?? {}) as Record<string, unknown>;
  if (!body.name || typeof body.name !== "string") {
    return reply.code(400).send({ error: "name_required" });
  }
  return createProfile(body as any);
});

app.get("/profiles/:pid", async (req, reply) => {
  const { pid } = req.params as { pid: string };
  const profile = await getProfile(pid);
  return profile ?? reply.code(404).send({ error: "not_found" });
});

app.patch("/profiles/:pid", async (req, reply) => {
  const { pid } = req.params as { pid: string };
  const profile = await patchProfile(pid, (req.body ?? {}) as any);
  return profile ?? reply.code(404).send({ error: "not_found" });
});

// ---- Matching + talks (teammate B fills in match.ts / talks.ts) ----
app.post("/match", async (req, reply) => {
  const { me, others } = (req.body ?? {}) as { me?: string; others?: string[] };
  if (!me || !Array.isArray(others)) {
    return reply.code(400).send({ error: "me_and_others_required" });
  }
  return match(me, others);
});

app.get("/talks/shared", async (req, reply) => {
  const { a, b } = req.query as { a?: string; b?: string };
  if (!a || !b) return reply.code(400).send({ error: "a_and_b_required" });
  return sharedTalks(a, b);
});

app
  .listen({ port: Number(process.env.PORT) || 3000, host: "0.0.0.0" })
  .catch((err) => {
    app.log.error(err);
    process.exit(1);
  });
