# HallwayTrack — build plan

> Cloud Native Hackathon (WeMakeDevs × KubeCon NA), Salt Lake City, Nov 9 2026.
> Submissions close **5:30 PM MT**.

## One-liner

Connect your GitHub, LinkedIn, Scholar and X, and say what you want from the conference.
HallwayTrack builds your profile, has you **swipe on talks and people**, builds your
schedule, and for every mutual match tells you **where they plan to be and when you're
both free**. It's all based on the schedules people share, so no live location and no
hardware are needed.

## Tracks we're entering

| Track | Prize | How we qualify |
|---|---|---|
| **Elasticsearch: "Find the Right Talk"** | $4K | Elastic is the core data layer: talks, profiles, swipes, matches. Hybrid search (BM25 + `semantic_text`, merged with RRF) for talk and people matching |
| **Dash0: "Stop Flying Blind"** | $4K | OpenTelemetry traces, logs and metrics on the API and the LLM calls, plus real-user monitoring on the frontend. A Dash0 dashboard and SLO. Use Agent0 to diagnose a real issue during the day and show it in the demo |
| **Sonar / Gitar: "Never Merge Broken"** | $4K | Every feature lands through a PR that Gitar reviewed. Custom rules in `.gitar/review/`. Let CI auto-fix a real failure |
| **Merge Forward: "Conferences for Everyone"** | iPad | Consent-first connections (no live tracking), accessibility filters, low-energy mode |
| Radar (optional) | $4K | Deploy on the provided cluster using `skyhook-io/cnh-starter` (Argo CD). Only if time allows |
| Best overall | DGX Spark | — |

## User flow

1. **Onboard (about 1 minute)**
   - Enter a GitHub username, LinkedIn profile PDF, Google Scholar name or ORCID, X handle (optional), and personal site (optional).
   - Answer two **required** questions (typed or spoken):
     - "What do you want out of this conference?"
     - "What could you help someone with?"
   - The profile builds live on screen as each source comes back.
2. **Review the profile.** It shows tags and a summary, each claim with its evidence. The user removes anything wrong.
3. **Swipe on talks.** Each card has a one-line reason ("You maintain X, and this talk covers Y"). Right means save, up means must-attend, left means skip.
4. **Swipe on people.** Each card has a reason ("Priya is looking for GPU autoscaling contributors, which you've done"). A match only happens when **both** swipe right.
5. **My schedule.** Saved talks without clashes, free blocks, and optional "where I'll be" blocks (sponsor hall, lunch, hallway track). Export to `.ics` or Google Calendar.
6. **Matches → meetups.** For each match:
   - Where they *plan* to be now and next.
   - Talks you share.
   - Suggested meetups ("Meet at the Room 155 door when 'eBPF at Scale' ends, 2:40 PM"). Accepting one adds it to both calendars.

## Profile ingestion

| Source | Method | Notes |
|---|---|---|
| GitHub | Public REST API (`/users/:u`, `/repos`, `/starred`, topics, README excerpts) | Most reliable. Starred repos are a strong interest signal |
| Google Scholar | **OpenAlex** or **Semantic Scholar** API, searched by name or ORCID | Scholar has no API and blocks scraping |
| LinkedIn | User uploads the profile PDF (Profile → More → Save to PDF) or pastes the About section | No scraping (it breaks their terms and hackathon rule 4) |
| X / Twitter | Bio plus pasted posts (optional) | The API is paid, so skip it |
| Website | Fetch, then readability extraction | Optional |
| Two questions | Free text or voice | **The key input for matching people** |

The LLM reads everything and fills in a structured profile. Fetch sources in parallel. Throw away
the raw text after extraction.

```json
{
  "name": "...", "role": "...", "seniority": "junior|mid|senior|staff+", "org": "...",
  "expertise": [{"topic": "eBPF observability", "weight": 0.8, "evidence": "github:org/repo"}],
  "interests": ["platform engineering", "GPU scheduling"],
  "goals": ["find_contributors", "learn", "hiring", "job_hunting", "meet_users"],
  "looking_for": "contributors for my k8s operator; learn multi-cluster networking",
  "offering": "KServe deployment, GPU autoscaling",
  "summary": "...",
  "accessibility": {"captions": true, "step_free": false, "low_energy": false}
}
```

Topic weight goes up with the amount of evidence, so one starred repo doesn't add a whole topic.

## Elastic data model

- **`talks`**:
  - `title`, `abstract`, `speakers[]`, `room`, `start`, `end`, `level`, `track`
  - `content` (`semantic_text`, made from title + abstract + speaker bios)
  - `captioned`, `recorded`
- **`profiles`**:
  - Keyword fields: `topics`, `role`, `seniority`, `goals`
  - `semantic_text` fields: `expertise_text`, `interests_text`, `looking_for_text`, `offering_text`
  - Speakers get a profile generated from their talk bio (`is_speaker: true`)
- **`swipes`**: `user`, `target_type (talk|person)`, `target_id`, `direction`, `ts`
- **`schedules`**: `user`, `items[]` (talk or custom block: `title`, `room/area`, `start`, `end`, `visibility`)
- **`meetups`**: `a`, `b`, `place`, `start`, `end`, `status (proposed|accepted|declined)`

Embeddings come from Elastic's built-in inference (Jina / ELSER) through `semantic_text`, so
there is no separate embedding service.

## Matching

### Person → talk
1. Find candidates with a hybrid query: keyword search on `topics` + semantic search on interests and expertise, merged with RRF.
2. Re-rank:
   - Level fit, based on seniority vs. talk `level`.
   - Mix of about 70% "deeper into what you know" and 30% "adjacent and new".
   - Boost talks that your mutual matches have saved.
   - Accessibility filters (captioned, step-free).
   - Remove talks that have started or that clash with must-attends.
3. Learn from swipes: a right swipe pulls the query toward that talk's content (Rocchio), a left swipe pushes it away slightly.
4. Generate the reason for each card with an LLM, using only that profile's evidence.

### Person → person (reciprocal)
```
score = 0.5 · need_offer + 0.3 · shared_interests + 0.2 · context
need_offer       = sqrt( sim(A.looking_for, B.offering) · sim(B.looking_for, A.offering) )
shared_interests = sim(A.expertise+interests, B.expertise+interests)
context          = overlap of saved talks + overlap of free time
```
- The geometric mean means a pair only scores high if **both** people benefit.
- Diversify the list with MMR so you don't get ten near-identical people.
- A match is created only on mutual right swipes.

## "Where will they be?": presence from the schedule

No live location, no Bluetooth, no hardware. Presence comes only from what each person
**chooses to put on their schedule**.

- **Schedule items:**
  - Saved talks, which already have a room and time.
  - Custom blocks: "Sponsor hall 3–4pm", "Lunch, outdoor tables", "Hallway track near Hall B".
  - Each item's visibility can be **Matches only** (the default), **Private**, or **Everyone**.
- **Match view:**
  - "Now: 'eBPF at Scale', Room 155 (planned) · Next: free 2:40–3:30 · Then: Sponsor hall"
  - Always labeled *planned*, never shown as live.
- **One-tap status** (optional and manual):
  - "Here now", "Running late", "Skipping this one", "Do not disturb".
  - Shown with a timestamp, and expires at the end of that slot.
  - This is the only "live" signal, and the person sends it deliberately.
- **Meetup engine**, for each pair of matches:
  1. **Shared talk:** propose meeting at that room's door when it ends.
  2. **Overlapping free time:** propose a spot between their previous rooms (coffee or hallway area) with the slot.
  3. Rank by time until the meetup and how close it is.
  - When both accept, it's added to both schedules and the `.ics` export.
- **Venue map:** a static floor plan with clickable room areas. Matches' planned spots for the current slot appear as avatars.
- **Privacy:**
  - Only mutual matches see shared items.
  - Unmatching or blocking hides everything immediately.
  - All data is deleted after the event.

## Accessibility (Merge Forward)

- Filters for captioned or recorded talks only.
- Step-free indicator on meetup spots.
- "Low-energy day" mode: fewer sessions, built-in breaks, quieter meetup spots.
- Pronoun field.
- Fully usable with a screen reader, plus buttons as an alternative to swiping.

## Stack

- **App:** Next.js (App Router) + TypeScript as a mobile-first installable web app. It runs on phones from a URL, with no app store.
- **API:** Next.js route handlers in the same app.
- **Data:** Elastic Serverless (Elasticsearch project) using the JS client.
- **LLM:** OpenAI (using the $50 credits) for profile extraction, card reasons and meetup wording.
- **Observability:**
  - OpenTelemetry Node SDK with OTLP export to Dash0, including spans for the LLM and Elastic calls.
  - Dash0 browser real-user monitoring.
  - Dash0 dashboard + SLO (p95 time to build a profile, and how often matching fails).
- **CI:** GitHub Actions for lint, typecheck and build. Gitar installed as a GitHub App, with rules in `.gitar/review/`.
- **Deploy:** Vercel for speed. Radar cluster through `cnh-starter` if we go for that track.

## Schedule data

1. Check whether the public KubeCon NA schedule (Sched) has an export or `.ics`, and use that if so.
2. Fallback: a hand-curated `data/talks.json` with about 60 talks covering a range of tracks and levels.
3. Seed about 30 **made-up personas** in `data/personas.json` so matching has something to show. They're clearly fictional, not real attendees.

## Timeline (from about 1:10 PM)

| Time | Work |
|---|---|
| 1:10–1:45 | Set up: Next.js scaffold (merged through a PR), Gitar installed, Elastic project, Dash0 key, CI, data loaded. *(Lunch at 1:00, so eat while setting up)* |
| 1:45–2:00 | Index mappings, talk ingest script, persona seed script |
| 2:00–2:30 | Kelsey panel. Listen with the laptop open |
| 2:30–3:30 | In parallel: **A** profile ingestion + LLM extraction · **B** talk swipe deck + hybrid search · **C** people matching + matches screen |
| 3:30–4:30 | Schedule builder, presence from the schedule, meetup engine, `.ics` export, venue map |
| 4:30–5:00 | Finish Dash0 setup (dashboard, SLO, Agent0 finds a bug we plant), accessibility filters, Radar deploy if there's time |
| 5:00–5:30 | README (setup + architecture + **AI-assistant disclosure**), demo rehearsal, **submit** |

## Demo (3 minutes)

1. Onboard live with a real GitHub username, and watch the profile build up as sources come back.
2. Swipe 3 talks, showing the reasons and how the deck updates.
3. Swipe people, then mutual-match with a teammate on a second phone.
4. Open the match: "Priya: Room 155 now, free 2:40", then accept the suggested meetup and it appears in both calendars.
5. Dash0: the trace of the profile-building pipeline, plus Agent0 explaining the bug we planted.
6. Show a Gitar-reviewed PR and its auto-fix.

## Risks

- **Running out of time.** Cut in this order: X ingestion, venue map, Radar, voice input.
- **The LLM misreads people.** Weight topics by evidence and let the user edit the profile.
- **Too few users at the demo.** The seeded personas cover this.
- **The schedule doesn't match where people really are.** Label everything *planned* and offer the one-tap status.
- **Rules.** Keep the repo public, have a README, disclose AI use, and be able to explain every part.

## Submission checklist

- [ ] Public repo + README with setup instructions
- [ ] AI-assistant use disclosed
- [ ] Every feature merged through a Gitar-reviewed PR
- [ ] Dash0 dashboard and SLO screenshots in the README
- [ ] Elastic mappings and queries documented
- [ ] Demo works on two phones
