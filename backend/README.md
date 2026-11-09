# Affinity backend

Fastify + TypeScript API for Affinity. It handles:
- profiles,
- talk recommendations and schedules,
- people matching,
- the "where we can meet" calendar reveal,
- meetups,
- radar glow tiers.

**Elasticsearch** is the data layer, using `semantic_text` + RRF hybrid search. **OpenAI** writes the profile tags and the reasons. **OpenTelemetry** sends traces and metrics to Dash0.

## Setup

```bash
cd backend
npm install
npm run seed     # creates the indices, then loads 48 talks + 20 fictional personas
npm run dev      # http://localhost:8080
npm run smoke    # runs the whole demo journey against the running server
```

The smoke test creates a "Demo User" profile, swipes and a match. Run `npm run seed` again before the demo to reset to a clean state.

### Environment

Variables are read from the repo-root `.env`, then from `backend/.env` (both are git-ignored).

| Variable | Required | Notes |
|---|---|---|
| `ELASTIC_URL` | ✅ | Elasticsearch endpoint, e.g. `https://<project>.es.<region>.elastic.cloud`. Also accepted: `ELASTICSEARCH_URL`, `ES_URL`, `ELASTIC_ENDPOINT`. You can set `ELASTIC_CLOUD_ID` instead |
| `ELASTIC_API_KEY` | ✅ | Encoded API key. Also accepted: `ELASTICSEARCH_API_KEY`, `ES_API_KEY` |
| `ELASTIC_INFERENCE_ID` | | Inference endpoint for `semantic_text`. Default `.jina-embeddings-v5-text-small` (Jina on Elastic's Inference Service). Set `default` to use the cluster's default |
| `OPENAI_API_KEY` | | Turns on LLM tags and reasons. Without it, keyword and template fallbacks are used. `OPENAI_API` also works |
| `OPENAI_MODEL` | | Default `gpt-4o-mini` |
| `GITHUB_TOKEN` | | Avoids GitHub's 60 requests/hour unauthenticated limit |
| `OTEL_EXPORTER_OTLP_ENDPOINT` + `OTEL_EXPORTER_OTLP_HEADERS` | | Standard OTLP export (for Dash0: `Authorization=Bearer <token>`) |
| `DASH0_ENDPOINT` + `DASH0_AUTH_TOKEN` (+ `DASH0_DATASET`) | | Shortcut instead of the two OTEL vars above |
| `DEMO_NOW` | | Pretend the current time is this ISO time, e.g. `2026-11-10T14:50:00-07:00`. Useful for "next room" during the demo |
| `PERSONA_AUTOLIKE_THRESHOLD` | | Default `0.45`. Personas match you back when your score with them is at or above this |
| `PORT` | | Default `8080` |

`GET /healthz` reports which of these are configured (as true/false only).

## API

All JSON. `pid` = profile id, `tid` = talk id. Times are ISO strings in conference time (`-07:00`).

| Method + path | What it does |
|---|---|
| `POST /profiles` | Body: `{name, role?, company?, pronouns?, github?, working_on, looking_for, offering, here_for[], status?}`. Fetches GitHub, extracts `topics` + `summary`, and stores the profile. Returns 201 + `Profile` |
| `GET /profiles/:pid` | Returns the `Profile` |
| `PATCH /profiles/:pid` | Edit any of `name, role, company, pronouns, working_on, looking_for, offering, here_for, topics, status (green\|yellow\|red), hide_next_room` |
| `GET /talks/recommended?pid=&limit=10` | `TalkCard[]`: future talks not yet swiped, each with a `reason` and `clashes_with` (clash with a must-attend) |
| `POST /swipes` | `{pid, target_type: "talk"\|"person", target_id, dir: "right"\|"up"\|"left"}`. `up` = must-attend (talks). A person swipe returns `{ok, match?}` when it's mutual |
| `GET /schedule/:pid` | `{pid, items[], free[], meetups[]}`: saved talks (with `must` and `clash` flags), free blocks of at least 20 minutes between 9:00 and 18:00, and accepted meetups |
| `GET /people/recommended?pid=&limit=10` | `PersonCard[]` with `score`, `reason`, `shared_topics`, `shared_talks_count` |
| `GET /matches/:pid` | `Match[]` |
| `GET /meet?a=&b=` | The **partial calendar reveal** (403 unless a and b are matched): `shared_talks`, `free_overlaps`, `their_next` (room + until, `planned: true`; null if hidden), `suggestions` (top 3), `meetups` |
| `POST /meetups` | `{a, b, place, start, end, label?}`. Creates a proposal (matched pairs only) |
| `PATCH /meetups/:id` | `{status: "accepted"\|"declined", pid?}`. If `pid` is given, it must be the invited person |
| `GET /meetups?pid=` | All meetups involving `pid` (incoming and outgoing) |
| `POST /radar/match` | `{me, others: [pid]}` → `[{pid, name, status, tier: "match"\|"strong"\|"good"\|"weak", score, reason}]`. People with 🔴 status are left out |
| `GET /healthz` | `{ok, config}` |

## How matching works

**Talks** (`talks.ts`):
1. Build the query from your `working_on` + `looking_for` + the titles of your last 5 saved talks (the swipe feedback loop).
2. An **RRF** retriever fuses a `semantic` query on `content` with a lexical query (`terms` on topics + `multi_match` on title and abstract). If RRF isn't available, it falls back to a single bool query.
3. Re-rank by level fit (a seniority guess from your role), plus a boost for talks your matches saved.

**People** (`people.ts`):
```
need_offer   = sqrt( sim(my looking_for, their offering) · sim(their looking_for, my offering) )
interests    = 0.5 · jaccard(topics) + 0.5 · sim(working_on)
talk_overlap = shared saved talks / min(4, my saved talks)
score        = 0.45·need_offer + 0.30·interests + 0.25·talk_overlap  (+0.10 if goals complement)
```
- Each `sim` is one `semantic` query over the profiles index, min-max normalized.
- The geometric mean means a pair only scores high when **both** people benefit.
- The list is diversified with MMR on topics.

**Meet** (`meet.ts`): reveals only the overlap of the two calendars. Suggestions are:
1. the door of a shared talk's room when it ends;
2. a coffee spot near the room each person is coming from, during times both are free (`data/places.json`).

## Data

- `data/talks.json`: 48 fictional talks over Nov 10–12 (4 rooms × 4 slots × 3 days).
- `data/personas.json`: 20 **fictional** people with complementary needs and saved talks, so matching, overlaps and meetups have something to show. Personas match you back automatically when the match is strong enough.
- `data/places.json`: room → nearby meeting spot.

## Observability

`src/otel.ts` starts the OpenTelemetry Node SDK before anything else. It provides:
- auto-instrumentation for HTTP, Fastify and the Elastic client;
- manual spans: `profile.build`, `github.fetch`, `openai.*`, `elastic.talks.hybrid`, `elastic.people.score`, `orbit.match.check`, `orbit.meet.view`;
- metrics: `orbit.swipes`, `orbit.matches.created`, `orbit.llm.duration`.

LLM reasons are cached in memory by `(pid, target)`.
