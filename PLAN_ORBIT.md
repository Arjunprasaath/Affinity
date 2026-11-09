# Affinity — build plan

> Cloud Native Hackathon (WeMakeDevs × KubeCon NA), Salt Lake City, Nov 9 2026.
> Submissions close **5:30 PM MT**. This plan was written at 2:27 PM, so we have **about 3 hours**.
>
> This is an alternative to [`PLAN.md`](PLAN.md) (HallwayTrack). The two can share the profile
> model and the Elastic `profiles` index. See "Relation to HallwayTrack" at the bottom.

## One-liner

**See who's around you at the conference, and who they are.**

Open the app and a radar shows the people physically near you. Tap a dot to see who that
person is, what they work on, and whether they're open to a chat. Then follow the arrow
to walk over.

## Pitch hook

> *"Today you walked past 50 people who could have changed your career. You'll never know who they were."*

- Networking is the #1 reason people attend (Freeman 2025: about half say it's their main reason to come back).
- 31% find networking awkward, and about 25% say they're bad at starting conversations (Freeman 2025).
- KubeCon NA 2025 had 9,388 attendees, **50% first-timers**, who arrive knowing nobody (CNCF transparency report).
- Existing apps (Whova, Brella, Sched) give you a **list of 9,000 people**. None tell you **who is standing 5 meters from you right now**.

### Why proximity works here when it failed elsewhere

Highlight, Banjo and Happn all failed for two reasons:
1. **Cold start:** nobody near you uses the app.
2. **Creepiness:** strangers know where you are.

A conference removes both:
- thousands of people are packed into one building;
- they came specifically to meet strangers.

Affinity's design also never sends anyone's location to a server (see Privacy).

## Features (in scope)

1. **📡 Radar.**
   - You're in the center; nearby people appear as dots on distance rings (< 2m, 2–5m, 5–15m).
   - Dots for people who share your topics are highlighted; the rest are dimmed.
   - On phones that support it, dots sit in the **real direction** of the person.
2. **🪪 Who they are.** Tap a dot to open a card with:
   - Name, role, company, pronouns (optional)
   - **What they're working on**, one line ("Migrating 40 clusters to Cilium")
   - Topic tags (eBPF, GitOps, platform eng, …)
   - **Here for:** hiring / job hunting / learning / finding contributors / meeting users
   - **"You both…"**: shared topics, computed server-side
   - Link to their GitHub
3. **🟢 Status.**
   - 🟢 Open to chat / 🟡 Ask first / 🔴 Heads down.
   - Shown on the dot and the card.
   - 🔴 hides you from radars completely. This is the privacy and accessibility feature: you're never approachable unless you choose to be.
4. **🧭 Find them.**
   - On a card, tap **Find**.
   - The screen becomes a big arrow and a distance ("3.2 m"), like AirTag precision finding.
   - This replaces a map, because indoor maps need location data we don't have.
5. **🔍 Filter.** Show only people who are hiring, first-timers, or people tagged with a topic you pick.

### Out of scope (cut on purpose)
- Matchmaking buzz/notifications, background detection, Android, venue maps, chat or DMs, schedule integration.
- **Bonus only if everything above works:**
  - "People I met today", a local list of people you were within 2m of for at least 30 seconds;
  - the big-screen dashboard (below).

## How it works

### Proximity (on-device, peer to peer)

| Layer | Apple framework | Gives us | Notes |
|---|---|---|---|
| Discovery | **MultipeerConnectivity** | "This person is nearby," plus their profile ID | Finds nearby iPhones over Bluetooth and peer-to-peer Wi-Fi, like AirDrop. No shared Wi-Fi network needed |
| Distance + direction | **NearbyInteraction** (UWB) | Exact distance in meters plus a direction vector | iPhone 11 or newer, **not the SE**. Peers swap `NIDiscoveryToken`s over the Multipeer session |
| Fallback | — | Just "nearby," no distance | For phones without UWB. The dot goes on the outer ring with the label "nearby" |

Steps:
1. Each phone **advertises** and **browses** the Multipeer service type `orbit-cnh`. The `discoveryInfo` carries `{ "pid": "<profile id>" }`.
2. When a peer is found, invite it and connect a session, then exchange NI discovery tokens.
3. Run one `NISession` per peer with `NINearbyPeerConfiguration(peerToken:)`. Use `distance` for the rings and `direction` for the angle and the Find arrow.
4. Check `NISession.deviceCapabilities` for `supportsPreciseDistanceMeasurement` and `supportsDirectionMeasurement`.
   - On newer iPhones, direction may require **camera assistance** (`isCameraAssistanceEnabled` + an ARKit session).
   - If direction isn't available, place dots at a stable random angle on the correct ring and hide the Find arrow, showing distance only.
5. The app fetches each profile card from the backend by `pid` and caches it.

**Required `Info.plist` keys:**
- `NSLocalNetworkUsageDescription`
- `NSBonjourServices` (`_orbit-cnh._tcp`, `_orbit-cnh._udp`)
- `NSNearbyInteractionUsageDescription`
- `NSCameraUsageDescription` (only if camera assistance is used)

### Backend (profiles only, no location)

- **API:** a small Node/TypeScript service with three endpoints:
  - `POST /profiles` creates or updates a profile;
  - `GET /profiles/:pid` returns one;
  - `POST /match` takes `{ me, others[] }` and returns, for each other person, their shared topics and a "You both…" line.
- **Data:** an Elasticsearch `profiles` index (same shape as HallwayTrack's):
  - keyword fields: `topics`, `here_for`, `status`
  - `semantic_text` fields: `working_on`, `expertise_text`
  - "You both…" comes from keyword overlap on `topics` plus semantic similarity of `working_on`, merged with RRF.
- **LLM:** OpenAI, using the $50 credits. It turns a GitHub username plus one sentence ("what are you working on?") into tags, then writes the "You both…" line. Cache the results.

### Onboarding (under 60 seconds)
1. Name, role, company.
2. GitHub username (optional). The backend pulls public repos and topics, and the LLM suggests tags.
3. "What are you working on?" in one line.
4. "Here for…" chips.
5. Status (defaults to 🟢).

## Privacy (our Merge Forward story)

- **No location ever leaves the phone.** The server never knows where anyone is. Proximity is computed only between the two phones involved.
- **You're visible only while the app is open.** Close it and you disappear.
- **🔴 Heads down** makes you invisible.
- Profiles hold only what you typed or approved, and are deleted after the event.
- The big-screen dashboard (bonus) is **demo-only and opt-in**: phones report "I see pid X at d meters" only when demo mode is on.

## Sponsor tracks

| Track | How we qualify | Priority |
|---|---|---|
| **Best overall** (DGX Spark) | The hook, plus a live two-phone demo | 🎯 Main target |
| **Merge Forward** (iPad) | Consent-first status, invisible mode, no location stored | 🎯 Main target |
| **Elasticsearch** ($4K) | The `profiles` index drives the "You both…" matching (keyword + semantic, merged with RRF) | ✅ Do it |
| Gitar ($4K) | Land features through PRs that Gitar reviews | If the repo is already set up for it |
| Dash0 ($4K) | Add OpenTelemetry to the backend: spans on the profile, match and LLM calls | Only if there's time |
| Radar ($4K) | Deploy the backend on the provided cluster | Skip unless far ahead |

## Stack

- **iOS app:** SwiftUI, iOS 17+, Xcode 16.4 (installed on Jenish's Mac). Frameworks: MultipeerConnectivity, NearbyInteraction.
- **Backend:** Node 22 + TypeScript (Fastify or Next.js route handlers), Elasticsearch JS client, OpenAI SDK.
- **Hosting:** anywhere reachable from the phones (Vercel, Render, or the Radar cluster).

## Device checklist (do this first, it's the biggest risk)

- [ ] **At least 2 iPhones, model 11 or newer (not SE)**, ideally 3.
- [ ] Each iPhone plugged into the Mac once. **Developer Mode** turned on (Settings → Privacy & Security → Developer Mode, which requires a restart).
- [ ] An Apple ID signed into Xcode. A free account works for up to 3 devices, and the app expires after 7 days.
- [ ] The first install works, and the phone trusts the developer (Settings → General → VPN & Device Management).
- [ ] On first launch, accept the **Local Network** and **Nearby Interaction** permission prompts.
- [ ] Bluetooth and Wi-Fi turned **on** on every phone. Being on the same network isn't required.
- ⚠️ The iOS **Simulator can't do Multipeer proximity or UWB**, so all proximity testing has to happen on real phones.

## Timeline (2:30 → 5:30 PM MT)

| Time | Work |
|---|---|
| 2:30–2:50 | **Devices first:** Developer Mode on the phones, signing set up, a "hello world" app installed on 2 phones. Backend scaffold, Elastic `profiles` index, about 15 seeded demo personas |
| 2:50–3:30 | **Proximity spike:** Multipeer discovery + NI distance between 2 phones, showing a raw "3.2 m" on screen. *If NI fights us, ship Multipeer "nearby" only and move on* |
| 3:30–4:15 | **Radar UI** (rings, dots, highlight, status colors) + **profile cards** pulled from the backend |
| 4:15–4:40 | **Find arrow** (NI direction), filters, onboarding screen, "You both…" line from `/match` |
| 4:40–5:00 | Polish, the 🔴 invisible mode, test with 3 phones, bonus items only if everything works |
| 5:00–5:30 | README (setup + architecture + **AI-assistant disclosure**), demo rehearsal, **submit by 5:30** |

**Cut order if behind:**
1. The bonus items
2. Filters
3. GitHub tag extraction (type the tags by hand)
4. The Find arrow (keep distance only)
5. NI (Multipeer "nearby" only)

## Demo (3 minutes)

1. **Hook** (20s): "You walked past 50 people today who could have changed your career."
2. **Problem** (30s): networking is why we come, and it's awkward and random. Apps give you a list of 9,000 people.
3. **Live** (90s):
   - Two teammates stand at opposite ends of the stage with Affinity open, and the phone screen is mirrored to the projector.
   - Dots appear on the radar: "Arjun · Platform eng · 8m · 🟢 Open to chat · You both work on Cilium."
   - Tap **Find**, and the arrow points across the stage while the distance counts down: 8m → 4m → 1m.
   - They meet and shake hands.
   - One teammate flips to 🔴 and vanishes from the radar.
4. **Why now** (20s): proximity apps died from cold start and creepiness, and a conference fixes both. No location ever leaves your phone.
5. **Close** (20s): "Never miss the person you needed to meet."

## Risks

| Risk | Mitigation |
|---|---|
| Signing or installing on phones eats the afternoon | Do the device checklist **first**, before writing any features |
| NI direction unavailable or flaky (camera-assistance requirement on newer iPhones) | Use distance-only rings, hide the arrow, and keep the demo about distance counting down |
| Multipeer not discovering peers | Check the Local Network permission and the `NSBonjourServices` keys, and toggle Bluetooth and Wi-Fi off and on. Test early, not at 5pm |
| Only iPhones can join | Say so in the pitch: "iOS-first for UWB; Android has UWB too on Pixel/Samsung, which is next" |
| Judges ask "isn't this creepy?" | No location is stored, you're visible only while the app is open, and 🔴 makes you invisible |
| Rules | Public repo, README, disclose AI assistant use, every team member able to explain the code |

## Relation to HallwayTrack ([`PLAN.md`](PLAN.md))

HallwayTrack deliberately avoids live location and works from **planned** schedules. Affinity is the
**live, in-the-room** layer. If the team wants to combine them:
- share the Elastic `profiles` index and the profile JSON shape;
- HallwayTrack handles *"who should I meet and when"*, and Affinity handles *"they're 4m away right now."*

The two plans are independent. Pick one to build today, given about 3 hours.

## Submission checklist

- [ ] Public repo + README with setup instructions (Xcode signing steps + backend env vars)
- [ ] AI-assistant use disclosed
- [ ] Works live on at least 2 iPhones
- [ ] Elastic mapping and `/match` query documented
- [ ] 30-second backup screen recording of the demo, in case the stage phones misbehave
