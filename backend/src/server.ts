import "./otel"; // must be first
import Fastify from "fastify";
import cors from "@fastify/cors";
import { config, configSummary } from "./config";
import { HttpError, badRequest } from "./errors";
import { createProfile, getProfile, patchProfile, publicProfile } from "./profile";
import { recommendTalks, getSchedule } from "./talks";
import { recommendPeople, swipe, listMatches, radarTiers } from "./people";
import { meetView } from "./meet";
import { proposeMeetup, updateMeetup, meetupsFor } from "./meetups";

export function buildServer() {
  const app = Fastify({ logger: { level: process.env.LOG_LEVEL ?? "info" } });
  app.register(cors, { origin: true });

  app.setErrorHandler((err, req, reply) => {
    if (err instanceof HttpError) return reply.status(err.statusCode).send({ error: err.message });
    const status = (err as any).statusCode;
    if (status && status < 500) return reply.status(status).send({ error: (err as Error).message });
    req.log.error(err);
    return reply.status(500).send({ error: "internal error", detail: (err as Error).message });
  });

  const limitOf = (q: any, d = 10) => {
    const n = Number(q?.limit ?? d);
    if (!Number.isFinite(n) || n < 1 || n > 50) throw badRequest("limit must be 1-50");
    return Math.floor(n);
  };

  app.get("/healthz", async () => ({ ok: true, config: configSummary() }));

  // Profiles
  app.post("/profiles", async (req, reply) => reply.status(201).send(publicProfile(await createProfile((req.body ?? {}) as any))));
  app.get<{ Params: { pid: string } }>("/profiles/:pid", async (req) => publicProfile(await getProfile(req.params.pid)));
  app.patch<{ Params: { pid: string } }>("/profiles/:pid", async (req) =>
    publicProfile(await patchProfile(req.params.pid, (req.body ?? {}) as any)),
  );

  // Talks + schedule
  app.get("/talks/recommended", async (req) => {
    const q = req.query as any;
    if (!q.pid) throw badRequest("pid is required");
    return recommendTalks(q.pid, limitOf(q));
  });
  app.get<{ Params: { pid: string } }>("/schedule/:pid", async (req) => getSchedule(req.params.pid));

  // Swipes (talks and people) + matches
  app.post("/swipes", async (req) => swipe((req.body ?? {}) as any));
  app.get("/people/recommended", async (req) => {
    const q = req.query as any;
    if (!q.pid) throw badRequest("pid is required");
    return recommendPeople(q.pid, limitOf(q));
  });
  app.get<{ Params: { pid: string } }>("/matches/:pid", async (req) => listMatches(req.params.pid));

  // Where we can meet (partial calendar reveal) + meetups
  app.get("/meet", async (req) => {
    const q = req.query as any;
    if (!q.a || !q.b) throw badRequest("a and b are required");
    return meetView(q.a, q.b);
  });
  app.post("/meetups", async (req, reply) => reply.status(201).send(await proposeMeetup((req.body ?? {}) as any)));
  app.patch<{ Params: { id: string } }>("/meetups/:id", async (req) => {
    const b = (req.body ?? {}) as any;
    return updateMeetup(req.params.id, b.status, b.pid);
  });
  app.get("/meetups", async (req) => {
    const q = req.query as any;
    if (!q.pid) throw badRequest("pid is required");
    return meetupsFor(q.pid);
  });

  // Orbit radar: glow tier for nearby people
  app.post("/radar/match", async (req) => {
    const b = (req.body ?? {}) as any;
    if (!b.me) throw badRequest("me is required");
    return radarTiers(b.me, b.others ?? []);
  });

  return app;
}

if (require.main === module) {
  const app = buildServer();
  app.log.info({ config: configSummary() }, "starting orbit backend");
  app.listen({ port: config.port, host: config.host }).catch((err) => {
    app.log.error(err);
    process.exit(1);
  });
}
