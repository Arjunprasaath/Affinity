# Orbit — build plan

> Cloud Native Hackathon (WeMakeDevs × KubeCon NA), Salt Lake City, Nov 9 2026.
> Written at **2:40 PM MT**. Submissions close at **5:30 PM**.
>
> One iPhone app that combines **HallwayTrack** (swipe on talks → your calendar → matched people →
> where you can meet) and **Orbit** (a live radar of who's near you).
> [`PLAN_ORBIT.md`](PLAN_ORBIT.md) remains as the detailed reference for the proximity work.

## One-liner

**Swipe to build your conference. Get matched with people who share your interests. See where you
can meet. When they're nearby, Orbit points the way.**

## Pitch hook

> *"Today you walked past 50 people who could have changed your career. You'll never know who they were."*

- Networking is the #1 reason people attend conferences, and many find it awkward.
- KubeCon NA 2025 had about 9,400 attendees, **half of them first-timers**.
- Sched gives you 300 talks in a list, and Whova gives you a list of 9,000 people. Neither tells you **which talks are for you, who you should meet, when you're both free, or that they're 4 meters away right now.**

## The user flow (5 steps)

```
1. Onboard ─► 2. Swipe talks ─► 3. My calendar ─► 4. Swipe people ─► 5. Match: where we can meet ─► 6. Orbit radar + Find
   profile      (Elastic)          (EventKit)        (reciprocal)       (partial calendar reveal)       (live, peer to peer)
```

1. **Onboard (under 60 seconds)**
   - Name, role, company, pronouns (optional), GitHub username.
   - **"What are you working on?"**, **"What are you looking for here?"**, **"What could you help someone with?"**
   - "Here for" chips: hiring / job hunting / learning / finding contributors / meeting users.
   - The backend builds a profile (GitHub + LLM). The app shows the topic tags it found, and the user removes any that are wrong, then confirms.
2. **Swipe talks**
   - Each card shows title, speaker, room, time, level, and **a one-line reason it fits you** ("You maintain an eBPF tracing repo, and this talk covers eBPF for network policy").
   - Right = save · Up = must-attend · Left = skip.
   - Cards that clash with a must-attend are marked "⚠️ clashes with …".
   - The deck adapts as you swipe: right-swiped talks pull the next recommendations toward them.
3. **My calendar**
   - Saved talks in a day timeline (Nov 10–12). Gaps show as **free blocks**.
   - Clashes are highlighted, with a one-tap choice to keep one.
   - **"Add all to Calendar"** writes the talks into the iPhone Calendar using EventKit.
4. **Swipe people**
   - The deck is recommended people with a reason: *"Priya is looking for GPU autoscaling contributors, which you've done · You've saved 3 of the same talks."*
   - Each card shows role, company, "Working on", "Here for", and shared topics. **No calendar details yet.**
   - Right = want to meet · Left = skip. **A match happens only when both swipe right.**
5. **Match: where we can meet**, with **partial calendar reveal**
   - Only after a mutual match, each person sees a **limited** view of the other's calendar:
     - ✅ **Talks you're both attending**, e.g. "eBPF at Scale · 3:30 · Room 155"
     - ✅ **Times you're both free**, e.g. "Tue 2:40–3:20", **without** what the other person is doing the rest of the time
     - ✅ **Where they'll be next** (planned), e.g. "Next: Room 155 until 3:40", labeled *planned*, never live
     - ❌ Never their full schedule, private talks, or any live location
   - **Meetup suggestions**, ranked:
     1. A shared talk: "Meet at the Room 155 door when 'eBPF at Scale' ends (3:40)"
     2. Overlapping free time: "Coffee by Hall B, Tue 2:45–3:15", a spot between both previous rooms
   - **Propose → Accept**: once both accept, the meetup is added to both in-app calendars and the iPhone Calendar.
6. **📡 Orbit radar** (live, in the room)
   - Shows nearby people as dots on distance rings (< 2m, 2–5m, 5–15m), found phone-to-phone.
   - **Your matches glow brightest**, recommended people glow softly, and everyone else is dimmed.
   - Tap a dot to open their card. For a match it shows the meetup and the times you're both free.
   - **Find:** a full-screen arrow + distance, like AirTag precision finding. Use it to walk over when your meetup is due, or to catch a match you didn't know was nearby.
   - **Status:** 🟢 open to chat / 🟡 ask first / 🔴 invisible (stops advertising completely).

## Privacy and consent (Merge Forward)

| Data | Who sees it |
|---|---|
| Profile (role, topics, working on) | Everyone at the event (that's the point), unless 🔴 |
| Your saved talks | Only you. Mutual matches see **only the talks you both saved** |
| Your free time | Only mutual matches, and only **overlaps** with their own free time |
| Your next planned room | Only mutual matches. You can turn it off ("Hide where I'll be") |
| Live proximity | Never leaves the phone. Computed between the two phones only. The server gets profile ids, never positions |

- Unmatching or blocking hides everything instantly.
- You're visible on the radar only while the app is open. 🔴 makes you invisible.
- 🟡 **Ask first** lets people who find approaching strangers hard still be discoverable on their own terms.
- All data is deleted after the event. Raw GitHub data is discarded after the profile is built.
- VoiceOver labels on every card and dot. The swipe decks have **Save / Skip buttons** as an alternative to swiping. The radar has a list view.

## Architecture

```
┌──────────────────────────── iPhone app (SwiftUI) ────────────────────────────┐
│ Onboarding │ Talks deck │ My Calendar │ People deck │ Matches │ Orbit radar   │
│                              │ EventKit                         │ Multipeer   │
│                              ▼                                  │ + NI (UWB)  │
│                         iPhone Calendar                         ▼             │
│                                                     ProximityManager          │
└───────────────┬──────────────────────────────────────────────────────────────┘
                │ HTTPS: profile ids, swipes, schedules (never location)
                ▼
┌──────────────────── Backend (Node 22 + TypeScript, Fastify) ─────────────────┐
│ profiles: GitHub ─► OpenAI extraction ─► Elastic                              │
│ talks:    recommend (hybrid + RRF + swipe feedback), schedule, clashes        │
│ people:   recommend (reciprocal + shared talks), swipes, mutual matches       │
│ meet:     shared talks + free-time overlap ─► suggestions, meetups            │
│ radar:    POST /radar/match {me, others[]} ─► glow tiers                      │
│ OpenTelemetry ─► Dash0                                                        │
└───────────────┬──────────────────────────────────────────────────────────────┘
                ▼
     Elastic Serverless: profiles · talks · swipes · schedules · meetups
```

## Team split (3 people)

Each person owns separate files, so nobody blocks anyone else after the first 10 minutes.

| | **A: Jenish (iOS core + Orbit)** | **B: Arjun (backend + Elastic)** | **C: third teammate (iOS screens)** |
|---|---|---|---|
| **Mission** | App shell + the live radar | The brain: profiles, recommendations, matching, meetups | The swipe → calendar → match experience |
| **Owns** | `ios/Orbit/App/**`, `ios/Orbit/Core/**` (API client, models), `ios/Orbit/Onboarding/**`, `ios/Orbit/Radar/**`, the Xcode project file | `backend/**`, `data/**` | `ios/Orbit/Talks/**`, `ios/Orbit/Calendar/**`, `ios/Orbit/People/**`, `ios/Orbit/Matches/**` |
| **Builds** | Device checklist + signing · Xcode project, tab bar, `APIClient` + `Models.swift` (from the contract below) · Onboarding · `ProximityManager` (Multipeer + NI) + `MockProximityManager` · RadarView, FindView, status · VoiceOver labels | Fastify scaffold with **stub** routes returning the sample JSON (by 2:55) · Elastic indices · `talks.json` + `personas.json` + seed · all endpoints below · deploy · OpenTelemetry → Dash0 | `SwipeDeck` view (reusable for talks and people) · TalksDeckView · MyCalendarView + EventKit export · PeopleDeckView · MatchesList + MatchDetailView (shared talks, free overlaps, next room, meetup suggestions, propose/accept) |
| **Done when** | Two iPhones see each other on the radar, matches glow, and Find points the way | A real GitHub user gets good talk recommendations, and seeded personas match and suggest sensible meetups, each in under 1 second | Swipe 5 talks → they're in the iPhone Calendar → swipe people → match → accept a meetup → it's in the calendar |

**Rules to avoid merge conflicts:**
- **Only Jenish edits the Xcode project file.** C creates Swift files in their own folders, and Jenish adds them to the project. Alternatively, C's screens can live in a local Swift package that Jenish adds once.
- `Models.swift` + `APIClient.swift` are written by Jenish **from the contract below** by 3:05. C uses them without editing (ask Jenish for changes).
- All of C's screens work against **stub JSON** at first, so C never waits for B.

**Hand-off points:**
- **2:55:** B pushes the stub backend. A pushes the Xcode shell + `Models.swift`/`APIClient.swift` by 3:05.
- **3:40:** B deploys the real talk and profile endpoints. A and C switch from stubs to the live URL.
- **4:20:** B's people, match and meet endpoints are live.
- **4:50:** everyone tests end to end on 3 phones.

## API contract (lock at 2:40–2:50)

All JSON, no auth (demo only). `pid` = profile id, `tid` = talk id.

| Method + path | Purpose | Response (shape) |
|---|---|---|
| `POST /profiles` | Create a profile from the onboarding answers + GitHub | `Profile` |
| `GET /profiles/:pid` · `PATCH /profiles/:pid` | Read / edit (tags, status, `hide_next_room`) | `Profile` |
| `GET /talks/recommended?pid=&limit=10` | Next cards for the talks deck (excludes talks already swiped) | `[TalkCard]` |
| `POST /swipes` | `{pid, target_type: "talk"\|"person", target_id, dir: "right"\|"up"\|"left"}` | `{ok, match?: Match}` (a person swipe can create a match) |
| `GET /schedule/:pid` | The user's saved talks, sorted, with clashes and free blocks | `Schedule` |
| `GET /people/recommended?pid=&limit=10` | Next cards for the people deck | `[PersonCard]` |
| `GET /matches/:pid` | Mutual matches | `[Match]` |
| `GET /meet?a=&b=` | The partial calendar reveal + meetup suggestions (only works if a and b are matched) | `MeetView` |
| `POST /meetups` · `PATCH /meetups/:id` | Propose `{a, b, start, end, place}` · accept or decline | `Meetup` |
| `POST /radar/match` | `{me, others: [pid]}` → glow tier for each nearby person | `[{pid, tier: "match"\|"strong"\|"good"\|"weak", reason}]` |
| `GET /healthz` | Health check | `{ok: true}` |

Main shapes:
```json
// Profile
{"pid":"p_8f3k2","name":"Arjun","role":"ML Engineer","company":"Acme","pronouns":"he/him",
 "github":"arjunprasaath","working_on":"Serving LLMs on k8s with GPU autoscaling",
 "looking_for":"Contributors for my operator; learn multi-cluster networking",
 "offering":"KServe deployment, GPU autoscaling","here_for":["finding_contributors","learning"],
 "topics":["kubernetes","gpu","llm-serving"],"summary":"…","status":"green","hide_next_room":false}

// TalkCard
{"tid":"t_42","title":"eBPF at Scale","speakers":["…"],"room":"Room 155",
 "start":"2026-11-10T15:00:00-07:00","end":"2026-11-10T15:40:00-07:00","level":"intermediate",
 "reason":"You maintain an eBPF tracing repo; this covers eBPF for network policy",
 "clashes_with":null}

// Schedule
{"pid":"p_8f3k2","items":[{"tid":"t_42","title":"…","room":"…","start":"…","end":"…","must":true,"clash":false}],
 "free":[{"start":"2026-11-10T15:40:00-07:00","end":"2026-11-10T16:30:00-07:00"}]}

// PersonCard
{"pid":"p_a1","name":"Priya","role":"…","company":"…","working_on":"…","here_for":["hiring"],
 "shared_topics":["kubernetes","gpu"],"shared_talks_count":3,"score":0.82,
 "reason":"Priya is looking for GPU autoscaling contributors, which you've done"}

// Match
{"pid":"p_a1","name":"Priya","matched_at":"…","reason":"…"}

// MeetView (the partial calendar reveal)
{"with":"p_a1",
 "shared_talks":[{"tid":"t_42","title":"eBPF at Scale","room":"Room 155","start":"…","end":"…"}],
 "free_overlaps":[{"start":"2026-11-10T15:40:00-07:00","end":"2026-11-10T16:10:00-07:00"}],
 "their_next":{"room":"Room 155","until":"2026-11-10T15:40:00-07:00","planned":true},
 "suggestions":[
   {"kind":"after_shared_talk","place":"Room 155 door","start":"…15:40","end":"…15:55","label":"Meet when 'eBPF at Scale' ends"},
   {"kind":"free_overlap","place":"Coffee by Hall B","start":"…15:45","end":"…16:10","label":"You're both free"}]}
```

## Backend details (B)

### Elastic indices
- **`profiles`**:
  - Keyword fields: `pid`, `role`, `company`, `status`, `here_for`, `topics`, `github`
  - `semantic_text` fields: `working_on`, `looking_for`, `offering`
  - Other: `hide_next_room` (boolean), `is_persona` (boolean)
- **`talks`**:
  - Keyword fields: `tid`, `room`, `level`, `track`, `topics`
  - Text fields: `title`, `abstract`, `speakers`
  - Dates: `start`, `end`
  - `content` (`semantic_text`) = title + abstract + speakers
- **`swipes`**: `pid`, `target_type`, `target_id`, `dir`, `ts`
- **`meetups`**: `id`, `a`, `b`, `place`, `start`, `end`, `status`

Embeddings come from Elastic's built-in inference (`semantic_text`), so there's no separate embedding service.
A schedule is just the talks a person swiped right or up, so it's computed from `swipes` + `talks` rather than stored.

### Profile building (`POST /profiles`)
1. If `github` is set, fetch in parallel with a 5-second timeout each: `/users/:u`, the 10 most recently pushed repos (description, language, topics), and 30 starred repos.
2. Use OpenAI **structured outputs** to extract `topics` (max 8), `summary` (one sentence) and `evidence[]`. A topic needs at least 2 signals, or has to appear in the user's own text.
3. If GitHub fails, build the profile from the free text alone.

### Talk recommendations (`GET /talks/recommended`)
1. Query text = `working_on` + `looking_for` + the titles of up to 5 talks the user swiped right on (feedback loop).
2. Hybrid search: a `semantic` query on `content` plus a `terms` query on `topics`, merged with **RRF**. Exclude talks already swiped. Keep only future talks.
3. Re-rank: boost talks whose level fits the person's seniority, and boost talks that the user's matches saved.
4. Mark clashes against must-attends.
5. `reason`: one batched OpenAI call per page of 10 (cached). Template fallback: "Covers {topic} from your work on {working_on}".

### Schedule (`GET /schedule/:pid`)
Saved talks sorted by `start`. Clash = overlapping times. Free blocks = gaps of 20 minutes or more
between 9:00 and 18:00 each day.

### People recommendations (`GET /people/recommended`)
```
need_offer   = sqrt( sim(me.looking_for, other.offering) · sim(other.looking_for, me.offering) )
interests    = 0.5 · jaccard(topics) + 0.5 · sim(me.working_on, other.working_on)
talk_overlap = |shared saved talks| / max(1, |my saved talks|)
score        = 0.45 · need_offer + 0.30 · interests + 0.25 · talk_overlap  (+0.1 if goals complement)
```
- Run one batched `semantic` query per direction over the candidates. The geometric mean means a pair only scores high if **both** people benefit.
- Use MMR to diversify the list. Exclude people already swiped and anyone with 🔴 status.

### Mutual match (`POST /swipes` with `target_type: person`)
- On a right swipe, check whether the other person has already swiped right on you. If so, create a match and return it.
- **Demo helper:** seeded personas automatically swipe right on anyone whose score with them is ≥ 0.6, so a match happens live on stage.

### Meet (`GET /meet?a=&b=`)
- Return 403 unless a and b are matched.
- `shared_talks` = the overlap of both schedules.
- `free_overlaps` = the intersection of both people's free blocks (15 minutes or more).
- `their_next` = b's next saved talk's room and end time. Omitted if `hide_next_room`.
- Suggestions:
  1. After each shared talk: "{room} door", for 15 minutes after it ends.
  2. For each free overlap: a spot near both people's previous rooms, from a small `places` map (rooms → nearest coffee/hallway spot).
  - Sort by start time, and return the top 3.

### Radar (`POST /radar/match`)
For each nearby pid:
- tier `match` if mutually matched;
- otherwise `strong` / `good` / `weak` from the people score (≥ 0.65 / ≥ 0.4).

Include a short reason.

### Seed data
- `data/talks.json`: about 50 talks over Nov 10–12, with rooms, times, levels and topics. Use the public KubeCon NA schedule if there's an export; otherwise curate by hand.
- `data/personas.json`: about 20 **made-up** personas (clearly fictional) with complementary needs, **each with 4–6 saved talks**, so overlaps, free time and meetups have data.
- `data/places.json`: room → nearby meeting spot.

### Observability (Dash0)
- OpenTelemetry Node SDK with OTLP export to Dash0.
- Spans for the GitHub, OpenAI and Elastic calls.
- Demo moment: Agent0 finds a planted slow path (uncached reasons), then show the fix.

## iOS details

### A: Jenish
- **Stack:** SwiftUI on iOS 17+. A tab bar with **Talks · Calendar · People · Matches · Orbit**.
- **Shared code:**
  - `APIClient` (async/await, base URL from config, with a `useStubs` flag that loads bundled JSON).
  - `Models.swift`, generated from the shapes above.
- **Proximity:**
  - **Discovery:** MultipeerConnectivity with service type `orbit-cnh` and `discoveryInfo = {pid, status}`. When a peer connects, exchange `NIDiscoveryToken`s and run one `NISession` per peer.
  - **Capabilities:** check `deviceCapabilities`. Fall back to distance only, or to "nearby" only on phones without UWB.
  - **Radar updates:** call `POST /radar/match` with the nearby pids, debounced 2 seconds and refreshed every 30 seconds.
- **`MockProximityManager`:** emits seeded persona pids at random distances. Use it in the Simulator and for the stage fallback.
- **`Info.plist` keys:**
  - `NSLocalNetworkUsageDescription`
  - `NSBonjourServices` (`_orbit-cnh._tcp`, `_orbit-cnh._udp`)
  - `NSNearbyInteractionUsageDescription`
  - `NSCalendarsWriteOnlyAccessUsageDescription` (for C's EventKit)
  - `NSCameraUsageDescription` (only if camera assistance is used)

### C: third teammate
- **`SwipeDeck<Card>`:** a generic stack of cards with drag gestures (right / left / up) **plus buttons**, used for both talks and people.
- **EventKit:**
  - Request permission with `EKEventStore().requestWriteOnlyAccessToEvents()` (iOS 17).
  - Create an `EKEvent` for each saved talk and each accepted meetup. Put the room in `location` and the reason in `notes`.
  - Store the event ids so a talk isn't added twice.
- **MyCalendarView:** a day timeline with talks as blocks, free time as dashed blocks, and clashes in red.
- **MatchDetailView:** sections for shared talks, times you're both free, their next room, and suggestion cards with a **Propose** button. Show incoming proposals with **Accept** / **Decline**. Include a "Find on radar" button that opens Orbit with that person selected.

## Sponsor tracks

| Track | How we qualify | Priority |
|---|---|---|
| **Elasticsearch: "Find the Right Talk"** ($4K) | Elastic is the whole data layer: hybrid talk recommendations with RRF and swipe feedback, reciprocal people matching, schedules and meetups | 🎯 |
| **Best overall** (DGX Spark) | Full journey: swipe → calendar → match → meet → live radar + Find | 🎯 |
| **Merge Forward** (iPad) | Partial-reveal consent model, no live location stored, 🔴/🟡, VoiceOver, button alternatives | 🎯 |
| **Dash0** ($4K) | Traced backend + Agent0 fix in the demo | ✅ if time allows |
| Gitar ($4K) | Features land through Gitar-reviewed PRs | Only if the repo is set up for it |
| Radar ($4K) | — | Skip |

## Timeline (2:40 → 5:30 PM MT)

| Time | A: Jenish | B: Arjun | C: third teammate |
|---|---|---|---|
| 2:40–2:50 | **All:** lock the API contract + folder ownership | | |
| 2:50–3:10 | Device checklist (Developer Mode, signing, hello-world on 2 iPhones). Xcode shell + tab bar + `Models`/`APIClient` with stubs, pushed by 3:05 | Fastify scaffold with stub routes, pushed by 2:55. Elastic project + indices. Start `talks.json` | Write stub JSON files. Start `SwipeDeck` |
| 3:10–3:40 | Proximity spike: Multipeer + NI on 2 phones. *If NI fights back, ship "nearby" only* | `POST /profiles` (GitHub + OpenAI), seed talks + personas, `/talks/recommended`, `POST /swipes`, deploy | TalksDeckView on stubs, then on live talks |
| 3:40–4:20 | Onboarding → `POST /profiles`. RadarView + `MockProximityManager` + `/radar/match` glow | `/schedule`, `/people/recommended`, mutual match + persona auto-like, `/matches` | MyCalendarView + EventKit "Add all to Calendar". PeopleDeckView |
| 4:20–4:50 | FindView, status 🟢🟡🔴, "Find on radar" hook-up from MatchDetail | `/meet` + `/meetups`, `/radar/match`, OpenTelemetry → Dash0, Agent0 fix | MatchesList + MatchDetailView (reveal + propose/accept → EventKit) |
| 4:50–5:10 | **All:** end-to-end on 3 phones, fix bugs. C records the 30-second backup video | | |
| 5:10–5:30 | **All:** README (setup + architecture + AI-assistant disclosure), rehearse, **submit by 5:30** | | |

### Cut order if behind
1. Dash0 extras (keep the basic traces)
2. LLM-generated reasons (fall back to the template)
3. Meetup propose/accept (show the suggestions only)
4. GitHub extraction (topics typed by hand)
5. Find arrow (distance only), then NearbyInteraction (Multipeer "nearby" only)
6. Orbit on real phones (keep the radar on `MockProximityManager`)

**Never cut:** swipe talks → calendar → swipe people → match → "where we can meet". That's the core story.

## Demo (3 minutes)

1. **Hook** (15s): "You walked past 50 people today who could have changed your career."
2. **Onboard** (20s): a real GitHub username, and the tags appear.
3. **Swipe talks** (25s): 4 swipes with reasons, then they appear in the iPhone Calendar.
4. **Swipe people** (25s): "Priya needs what you offer, and you share 3 talks." Swipe right, **it's a match** (she already liked you).
5. **Where we can meet** (25s): shared talk at 3:00 in Room 155, both free 3:40–4:10 → propose "Room 155 door at 3:40" → accepted → it's in both calendars.
6. **Orbit** (40s): with the phone mirrored, Priya's dot **glows** on the radar. Tap **Find**, the arrow and distance count down 8m → 1m, handshake. She flips to 🔴 and vanishes.
7. **Under the hood** (20s): the Elastic RRF query + reciprocal score, and a Dash0 trace. "No location ever leaves your phone, and matches see only the overlap of your calendars."

## Risks

| Risk | Mitigation |
|---|---|
| Too much iOS UI for 3 hours | C has a reusable `SwipeDeck` for both decks. Stubs from minute one. Cut-order list above |
| Signing or installing on iPhones eats time | Jenish does the device checklist first. Everyone else builds in the Simulator against `MockProximityManager` |
| Conflicts in the Xcode project file | Only Jenish edits the project. C works only in their own folders |
| NI or Multipeer flaky on stage | Distance only, then the mock radar, plus the backup video |
| Empty data during the demo | Personas with saved talks + auto-like make matches and overlaps appear |
| "Isn't this creepy?" | Partial reveal only after a mutual match, nothing about location stored, 🔴 invisible, 🟡 ask first |
| Rules | Public repo, README, AI use disclosed, everyone can explain their part |

## Submission checklist

- [ ] Public repo + README (Xcode signing steps, backend env vars, seed command)
- [ ] AI-assistant use disclosed
- [ ] The full journey works on at least 2 iPhones
- [ ] Elastic mappings + recommendation, matching and meet queries documented
- [ ] Dash0 trace screenshot
- [ ] 30-second backup screen recording
- [ ] Submitted before 5:30 PM
