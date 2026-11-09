# Orbit — combined build plan

> Cloud Native Hackathon (WeMakeDevs × KubeCon NA), Salt Lake City, Nov 9 2026.
> Written at **2:30 PM MT**. Submissions close at **5:30 PM**, which leaves **3 hours**.
>
> This plan merges **HallwayTrack** (profiles, reciprocal matching, talk search) and **Orbit**
> (live iPhone radar) into a single product. It replaces both earlier plans.
> [`PLAN_ORBIT.md`](PLAN_ORBIT.md) remains as the detailed reference for the iOS proximity work.

## One-liner

**Orbit knows who you should meet, where they're heading next, and when they're 4 meters away.**

Open the app and a radar shows the people physically near you. The ones you should meet glow.
Tap one to see why ("Priya needs what you offer") and which talk you'd both like next. Then
follow the arrow to walk over.

## Pitch hook

> *"Today you walked past 50 people who could have changed your career. You'll never know who they were."*

- Networking is the #1 reason people attend conferences, and many find it awkward.
- KubeCon NA 2025 had about 9,400 attendees, **half of them first-timers**.
- Whova, Brella and Sched give you a **list of 9,000 people**. Orbit tells you **which of the people standing next to you is worth talking to, and why**.
- Proximity apps like Highlight and Banjo died from cold start and creepiness. A conference fixes the cold start (everyone is in one building to meet strangers). Our design fixes the creepiness: no location ever goes to a server, you're visible only while the app is open, and 🔴 makes you invisible.

## How the two ideas fit together

| Layer | From | Answers | Runs on |
|---|---|---|---|
| **Profile** | HallwayTrack | Who you are, what you need, what you offer | Backend + Elastic + LLM |
| **Match** | HallwayTrack | Is this person worth meeting, and why | Backend + Elastic |
| **Where next** | HallwayTrack (cut down) | Which talk you'd both like, and when and where it is | Backend + Elastic |
| **Radar + Find** | Orbit | Who is near me **right now**, and which way to walk | iPhone, peer to peer |

The radar finds **who is nearby**, the backend decides **who matters**, and the card says **why and where next**.

## Features

### In scope (must ship)

1. **Onboarding (under 60 seconds)**
   - Name, role, company, pronouns (optional).
   - GitHub username (optional but encouraged).
   - **"What are you working on?"** (one line)
   - **"What are you looking for here?"** (free text, plus "Here for" chips: hiring / job hunting / learning / finding contributors / meeting users)
   - **"What could you help someone with?"** (free text)
   - The backend builds the profile, then the app shows the topic tags it found. The user can remove any of them, then confirms.
2. **📡 Radar**
   - You're in the center, with nearby people as dots on distance rings (< 2m, 2–5m, 5–15m).
   - **Dot glow = match score** from `/match`: strong matches glow, the rest are dimmed.
   - Status color on each dot: 🟢 open to chat / 🟡 ask first. 🔴 people don't appear at all.
   - On phones with UWB direction, dots sit in the person's real direction. Otherwise they get a stable random angle.
3. **🪪 Person card** (tap a dot):
   - Name, role, company, pronouns, status, "Here for" chips, GitHub link
   - **"Working on"**, one line
   - **"Why you should meet"**, a reason generated from the reciprocal match ("Priya is looking for GPU autoscaling contributors, which you've done")
   - **"A talk for both of you"**, e.g. *"eBPF at Scale · 3:30 PM · Room 155"* (from `/talks/shared`)
   - **Find** button
4. **🧭 Find:** a full-screen arrow plus the distance ("3.2 m"), like AirTag precision finding. If the phone can't measure direction, show distance only.
5. **🟢🟡🔴 Status:** one tap from the radar screen. 🔴 stops advertising completely.

### Stretch (only once the demo works end to end)

- Filter chips: show only hiring, first-timers, or one topic.
- "People I met today": a list kept only on the phone, of people within 2m for at least 30 seconds.
- LinkedIn profile PDF upload and OpenAlex (Scholar-style) papers as extra profile sources.
- Dash0 dashboard + SLO.
- A big-screen demo dashboard (opt-in demo mode only).

### Cut on purpose

- Talk and people swipe decks, schedule builder, `.ics` export, meetup suggestions, venue map
- Web app, Android, background detection, chat/DMs, X ingestion, voice input
- Radar (Skyhook) track deploy

## Architecture

```
┌──────────────────────── iPhone (SwiftUI) ────────────────────────┐
│ Onboarding ─► POST /profiles                                     │
│                                                                  │
│ ProximityManager                                                 │
│   MultipeerConnectivity  (discover peers, discoveryInfo={pid})   │
│   NearbyInteraction      (distance + direction per peer)         │
│        │ nearby pids                                             │
│        ▼                                                         │
│ RadarView ─► POST /match {me, others[]} ─► glow + reasons        │
│ PersonCard ─► GET /profiles/:pid, GET /talks/shared?a=&b=        │
│ FindView   (NI direction/distance only, no network)              │
└──────────────────────────────────────────────────────────────────┘
                 │ HTTPS (profile ids only, never location)
                 ▼
┌──────────────── Backend (Node 22 + TypeScript, Fastify) ─────────┐
│ /profiles   GitHub API ─► OpenAI extraction ─► Elastic profiles   │
│ /match      reciprocal scoring over Elastic semantic_text + RRF   │
│ /talks/shared  hybrid query over Elastic talks using both people  │
│ OpenTelemetry ─► Dash0 (spans for Elastic, OpenAI, GitHub calls)  │
└──────────────────────────────────────────────────────────────────┘
                 │
                 ▼
        Elastic Serverless: profiles, talks
```

## Team split (3 people)

Each person owns separate files, so nobody blocks anyone else after the first 10 minutes.

| | **A: Jenish (iOS)** | **B: Arjun (search + matching)** | **C: third teammate (platform + profiles)** |
|---|---|---|---|
| **Mission** | Make the radar and Find work on real iPhones | Make the matches smart: Elastic is the brain | Give everyone a running backend, real profiles and observability |
| **Owns** | `/ios/**` | `backend/src/elastic.ts`, `match.ts`, `talks.ts`, `scripts/seed.ts`, `/data/**` | `backend/src/server.ts`, `profile.ts`, `otel.ts`, deploy, `README.md` |
| **Builds** | Device checklist, `ProximityManager` (Multipeer + NI), `MockProximityManager`, Onboarding, RadarView, PersonCard, FindView, status (🟢🟡🔴), VoiceOver labels, list view | Elastic project + both index mappings, `talks.json` (about 50 talks) + `personas.json` (about 20 personas), seed script, `POST /match` (reciprocal scoring, tiers, reasons, caching), `GET /talks/shared` (hybrid + RRF) | Fastify scaffold with stub routes returning the contract's sample JSON, `POST/GET/PATCH /profiles` (GitHub fetch + OpenAI structured extraction + index), public deploy, OpenTelemetry → Dash0, planted slow path + Agent0 fix, README + AI disclosure, backup demo video |
| **Done when** | Two iPhones show each other on the radar with glow from `/match`, and Find points the way | `/match` returns sensible strong matches for seeded personas in under 1 second, and `/talks/shared` returns 3 relevant upcoming talks | The deployed URL serves every endpoint, a real GitHub username becomes a good profile, and a trace of `/match` is visible in Dash0 |
| **Unblocks** | — | A (glow, reasons, talks) | A (stub endpoints by 3:00, real `/profiles` by 3:40) and B (scaffold + deploy) |

**Hand-off points:**
- **2:40:** C pushes the scaffold with **stub** endpoints returning the sample JSON from the API contract. A builds against the stubs, and B replaces them route by route.
- **3:00:** B finishes the Elastic indices + seed. C's `/profiles` writes into `profiles`.
- **4:00:** the backend is deployed to a public URL. A switches the app from stubs to it.
- **4:50:** everyone tests end to end on 3 phones.

## API contract (agree on this first, then build in parallel)

Base URL is set in the app's config. All JSON. No auth (demo only).

### `POST /profiles` (create or update)
Request:
```json
{
  "pid": "optional; server generates if missing",
  "name": "Arjun", "role": "ML Engineer", "company": "Acme", "pronouns": "he/him",
  "github": "arjunprasaath",
  "working_on": "Serving LLMs on Kubernetes with GPU autoscaling",
  "looking_for": "Contributors for my operator; learn multi-cluster networking",
  "offering": "KServe deployment, GPU autoscaling",
  "here_for": ["finding_contributors", "learning"],
  "status": "green"
}
```
Response: the stored profile, including the extracted fields:
```json
{
  "pid": "p_8f3k2",
  "...": "all request fields",
  "topics": ["kubernetes", "gpu", "llm-serving", "kserve"],
  "summary": "Builds ML serving infra on Kubernetes...",
  "evidence": [{"topic": "kserve", "source": "github:arjunprasaath/kserve-demo"}]
}
```

### `GET /profiles/:pid`
Returns the profile above. The app caches it for the session.

### `PATCH /profiles/:pid`
For edits after review, e.g. `{ "topics": [...], "status": "yellow" }`.

### `POST /match`
Request: `{ "me": "p_8f3k2", "others": ["p_a1", "p_b2", "p_c3"] }`
Response, sorted by score:
```json
[
  {
    "pid": "p_a1",
    "score": 0.82,
    "tier": "strong",
    "reason": "Priya is looking for GPU autoscaling contributors, which you've done.",
    "shared_topics": ["kubernetes", "gpu"]
  }
]
```
Tiers: `strong` ≥ 0.65, `good` ≥ 0.4, otherwise `weak`. The app uses the tier for glow and dimming.

### `GET /talks/shared?a=<pid>&b=<pid>`
Returns up to 3 upcoming talks both people would like:
```json
[{"id": "t_42", "title": "eBPF at Scale", "room": "Room 155", "start": "2026-11-10T15:30:00-07:00", "why": "Both of you work on Cilium"}]
```

### `GET /healthz`
Returns `{ "ok": true }`.

## Backend details

### Profile building (`POST /profiles`)
1. If `github` is set, fetch these in parallel (with a 5-second timeout each):
   - `GET /users/:u`
   - `GET /users/:u/repos?sort=pushed&per_page=10` (names, descriptions, languages, topics)
   - `GET /users/:u/starred?per_page=30` (interest signal)
2. Send everything to OpenAI with **structured outputs** (JSON schema), asking for: `topics` (max 8, lowercase kebab-case), `summary` (one sentence), and `evidence[]`.
   - Weight topics by evidence: a topic needs at least 2 signals, **or** has to appear in the user's own text.
3. Index into `profiles`, then return the profile.
4. If GitHub fails or there's no username, build the profile from the free text alone.

### Elastic `profiles` index
```json
{
  "mappings": {
    "properties": {
      "pid":          {"type": "keyword"},
      "name":         {"type": "text"},
      "role":         {"type": "keyword"},
      "company":      {"type": "keyword"},
      "status":       {"type": "keyword"},
      "here_for":     {"type": "keyword"},
      "topics":       {"type": "keyword"},
      "github":       {"type": "keyword"},
      "summary":      {"type": "text"},
      "working_on":   {"type": "semantic_text"},
      "looking_for":  {"type": "semantic_text"},
      "offering":     {"type": "semantic_text"},
      "is_persona":   {"type": "boolean"}
    }
  }
}
```

### Elastic `talks` index
```json
{
  "mappings": {
    "properties": {
      "id":       {"type": "keyword"},
      "title":    {"type": "text"},
      "abstract": {"type": "text"},
      "speakers": {"type": "text"},
      "room":     {"type": "keyword"},
      "start":    {"type": "date"},
      "end":      {"type": "date"},
      "level":    {"type": "keyword"},
      "track":    {"type": "keyword"},
      "topics":   {"type": "keyword"},
      "content":  {"type": "semantic_text"}
    }
  }
}
```
`content` = title + abstract + speakers. Embeddings come from Elastic's built-in inference,
so there is no separate embedding service.

### Reciprocal matching (`POST /match`)
For each `other` in the request:
```
need_offer   = sqrt( sim(me.looking_for, other.offering) · sim(other.looking_for, me.offering) )
shared       = 0.5 · jaccard(me.topics, other.topics) + 0.5 · sim(me.working_on, other.working_on)
goal_bonus   = 0.1 if the goals complement each other (hiring↔job_hunting, finding_contributors↔learning)
score        = 0.55 · need_offer + 0.35 · shared + goal_bonus   (capped at 1)
```
- `sim(text, field)` is a `semantic` query on that field, filtered to `pid: other`, with the score normalized to 0–1. For speed, run one `semantic` query per direction over **all** the `others` at once (`terms: {pid: others}`), then read off each person's score.
- The geometric mean in `need_offer` means a pair only scores high if **both** people benefit.
- `reason`: one short OpenAI call per **strong or good** match, using only the two profiles. Cache by `(me, other)` pair. Weak matches get a reason built from a template ("You both work on {topic}").
- Skip anyone with `status: red`.

### Talk search (`GET /talks/shared`)
- Build the query text from both people's `working_on` and `looking_for`, joined together.
- Run a hybrid query: a `semantic` query on `content` plus a `terms` query on `topics` (union of both people's topics), merged with **RRF**.
- Keep only talks with `start > now`, and return the top 3.
- `why`: template text from the shared topics, or an LLM line if there's time.

### Seed data
- `data/talks.json`: about 50 talks covering several tracks and levels, with rooms and times on Nov 10–12. Use the public KubeCon NA schedule if an export exists; otherwise curate by hand.
- `data/personas.json`: about 20 **made-up** personas (clearly fictional, not real attendees) with complementary needs, so matching has something to show.
- `scripts/seed.ts`: creates both indices and bulk-loads both files.

### Observability (Dash0)
- Use the OpenTelemetry Node SDK with OTLP export to Dash0.
- Auto-instrument HTTP, and add manual spans for `github.fetch`, `openai.extract`, `openai.reason`, `elastic.match` and `elastic.talks`.
- Log each match as a structured event (score and tier only, no personal data).
- Demo moment: plant a slow path (for example, no cache on `reason`), let Agent0 find it, fix it, and show the before/after in the demo.

## iOS details (summary; full detail in [`PLAN_ORBIT.md`](PLAN_ORBIT.md))

- **Stack:** SwiftUI on iOS 17+, using MultipeerConnectivity and NearbyInteraction.
- **Discovery:**
  - Every phone advertises and browses the service type `orbit-cnh`, with `discoveryInfo = {"pid": "<pid>"}`.
  - When a peer is found: invite it, connect the session, and exchange `NIDiscoveryToken`s.
  - Then run one `NISession` per peer.
- **Capabilities:** check `NISession.deviceCapabilities`. Direction may need camera assistance on newer iPhones. If it isn't available, fall back to distance only. A phone with no UWB shows peers as "nearby" on the outer ring.
- **Match refresh:** when the set of nearby pids changes, call `POST /match` (debounced 2 seconds), cache the results, and refresh every 30 seconds.
- **Status:**
  - 🔴 stops advertising and browsing.
  - 🟡 and 🟢 are sent to the backend (`PATCH /profiles/:pid`).
  - The status is also included in `discoveryInfo`, so the radar updates instantly.
- **`Info.plist` keys:**
  - `NSLocalNetworkUsageDescription`
  - `NSBonjourServices` (`_orbit-cnh._tcp`, `_orbit-cnh._udp`)
  - `NSNearbyInteractionUsageDescription`
  - `NSCameraUsageDescription` (only if camera assistance is used)
- **Simulator:** it can't do proximity. Use a `MockProximityManager` that emits fake peers (seeded persona pids at random distances) so the UI and backend integration can be built without phones.

## Privacy and accessibility (Merge Forward)

- **No location ever leaves the phone.** Proximity is computed only between the two phones involved. The backend receives profile ids, never positions or distances.
- **Visible only while the app is open.** 🔴 makes you invisible instantly.
- **🟡 Ask first** lets people who find approaching strangers hard (or who are neurodivergent, or tired) still be discoverable on their own terms.
- Profiles hold only what you typed or approved. The raw GitHub data is discarded after extraction, and all profiles are deleted after the event.
- The app works with VoiceOver: dots have accessible labels ("Priya, strong match, about 3 meters, ahead-left"), and there's a list view as an alternative to the radar.

## Sponsor tracks

| Track | How we qualify | Priority |
|---|---|---|
| **Best overall** (DGX Spark) | Hook + live two-phone demo + the "why you should meet" reason | 🎯 |
| **Merge Forward** (iPad) | Consent-first status, no location stored, VoiceOver, 🟡 Ask first | 🎯 |
| **Elasticsearch** ($4K) | Elastic is the core data layer: profiles, reciprocal semantic matching, hybrid talk search with RRF | 🎯 |
| **Dash0** ($4K) | Traced backend, Agent0 finding the planted slow path, dashboard | ✅ if time allows |
| Gitar ($4K) | Features land through Gitar-reviewed PRs | Only if the repo is set up for it |
| Radar ($4K) | — | Skip |

## Repo layout

```
/ios/Orbit.xcodeproj            SwiftUI app (Jenish)
/backend/src/server.ts          Fastify app + routes (Arjun)
/backend/src/elastic.ts         client, mappings, queries
/backend/src/profile.ts         GitHub fetch + OpenAI extraction
/backend/src/match.ts           reciprocal scoring + reasons
/backend/src/talks.ts           shared-talk hybrid query
/backend/src/otel.ts            OpenTelemetry → Dash0
/backend/scripts/seed.ts        index creation + bulk load
/data/talks.json  /data/personas.json
README.md                       setup, architecture, AI-assistant disclosure
```

Backend env vars: `ELASTIC_URL`, `ELASTIC_API_KEY`, `OPENAI_API_KEY`, `GITHUB_TOKEN` (optional, to avoid rate limits), `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_EXPORTER_OTLP_HEADERS` (Dash0 auth).

## Timeline (2:30 → 5:30 PM MT)

| Time | A: Jenish (iOS) | B: Arjun (search + matching) | C: platform + profiles |
|---|---|---|---|
| 2:30–2:40 | **All:** lock the API contract, agree on file ownership, create the folders | | |
| 2:40–3:00 | Device checklist: Developer Mode, signing, hello-world on 2 iPhones | Elastic Serverless project, both index mappings, start `talks.json` | Fastify scaffold with **stub routes** returning sample JSON, pushed by 2:40. Then deploy it (Vercel/Render) |
| 3:00–3:40 | Proximity spike: Multipeer + NI distance on 2 phones. *If NI fights back, ship Multipeer "nearby" only* | Finish `talks.json` + `personas.json`, run `seed.ts`, then the first version of `/talks/shared` | `/profiles` endpoints: GitHub fetch + OpenAI structured extraction + index into `profiles` |
| 3:40–4:20 | `MockProximityManager`, RadarView, Onboarding → `POST /profiles` | `/match`: reciprocal scoring, tiers, template reasons, then LLM reasons with caching | OpenTelemetry → Dash0 (HTTP, Elastic, OpenAI, GitHub spans). Redeploy with the real routes |
| 4:20–4:50 | Glow from `/match`, PersonCard (reason + shared talk), FindView, status | Tune weights on the personas, batch queries, warm the cache. Help A with integration | Planted slow path → Agent0 finds it → fix. Start the README |
| 4:50–5:10 | **All:** test with 3 phones end to end, fix bugs. C records the 30-second backup video | | |
| 5:10–5:30 | **All:** finish the README, rehearse the demo (A drives the phones, B explains Elastic, C explains Dash0 + privacy), **submit by 5:30** | | |

### Cut order if behind
1. Stretch items
2. Dash0 extras (keep the basic traces)
3. LLM-generated reasons (fall back to the template)
4. GitHub extraction (topics typed by hand)
5. The Find arrow (distance only)
6. NearbyInteraction (Multipeer "nearby" only)

The **glowing radar + reason + talk for both** experience is the core. Protect it.

## Demo (3 minutes)

1. **Hook** (20s): "You walked past 50 people today who could have changed your career."
2. **Problem** (20s): networking is why we come. Apps hand you a list of 9,000 people and no way to know who's next to you.
3. **Live** (100s), with one phone mirrored to the projector:
   - Onboard live with a real GitHub username, and the tags appear.
   - The radar shows the teammates on stage plus seeded personas. **One dot glows.**
   - Tap it: "Why you should meet: Priya needs GPU autoscaling help, which you've done. A talk for both of you: eBPF at Scale, 3:30, Room 155."
   - Tap **Find**, and the arrow points across the stage while the distance counts down. They shake hands.
   - Priya flips to 🔴 and vanishes from the radar.
4. **Under the hood** (25s): the Elastic reciprocal query, plus the Dash0 trace of one `/match` call and the bug Agent0 found.
5. **Close** (15s): "No location ever leaves your phone. Never miss the person you needed to meet."

## Risks

| Risk | Mitigation |
|---|---|
| Signing or installing on iPhones eats the afternoon | Jenish does the device checklist **first**. The UI is built against `MockProximityManager` in the meantime |
| NI direction unavailable or flaky | Distance-only rings. The demo focuses on the distance counting down |
| Multipeer doesn't find peers | Check the Local Network permission and the Bonjour keys, toggle Bluetooth and Wi-Fi, and test by 3:40 |
| `/match` too slow during the demo | Batch the semantic queries, cache reasons, warm the cache before going on stage |
| The LLM gets a profile wrong | Weight topics by evidence and let the user review the tags |
| Too few real users | Seeded personas appear through the mock or a demo-mode toggle |
| "Isn't this creepy?" | No location is stored, you're visible only while the app is open, 🔴 makes you invisible, 🟡 means ask first |
| Rules | Public repo, README, AI use disclosed, both of us able to explain every part |

## Submission checklist

- [ ] Public repo + README with setup (Xcode signing, backend env vars, seed command)
- [ ] AI-assistant use disclosed in the README
- [ ] Works live on at least 2 iPhones
- [ ] Elastic mappings plus the `/match` and `/talks/shared` queries documented
- [ ] Dash0 trace screenshot in the README
- [ ] 30-second backup screen recording
- [ ] Submitted before 5:30 PM
