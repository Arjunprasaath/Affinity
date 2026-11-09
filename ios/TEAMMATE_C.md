# Teammate C — the swipe → calendar → match screens

Everything in `Talks/`, `Calendar/`, `People/`, `Matches/` and `Components/` is yours. The
`Orbit/` folder is a **synced** Xcode group, so new files compile automatically — you never
touch the project file, and you never block Jenish.

## What's here now

| File | What it does |
|---|---|
| `Components/SwipeDeck.swift` | The generic card stack. Drag right/left/up **and** a button for each, a SAVE/SKIP/MUST watermark that follows the drag, VoiceOver announcements. Also holds `deckCard()`, `Chip`, `ChipRow`. |
| `Components/ConferenceTime.swift` | All date formatting, pinned to `America/Denver`. Use it instead of `Date.formatted` so a phone in another time zone doesn't split "Nov 10" in two. |
| `Talks/TalkCardView.swift` | One talk card: time, room, level, speakers, abstract, the **reason** box, and the clash warning. |
| `Talks/TalksDeckView.swift` | The talks deck. POSTs each swipe, refills when 2 cards are left, counters at the top, "See calendar" when you've saved something. |
| `Calendar/CalendarExporter.swift` | EventKit. Write-only access (iOS 17), one event per talk and per accepted meetup, a 10-minute alarm, and it remembers the event ids so nothing is added twice. |
| `Calendar/MyCalendarView.swift` | Day picker, timeline with solid talk blocks and dashed free blocks, red clashes with a **"fix"** sheet that keeps one, and **Add all to Calendar**. |
| `People/PersonCardView.swift` | Person card: role, company, working on, here-for, shared topics, shared-talk **count**, the reason, and the "their schedule stays private" line. Plus `Avatar`. |
| `People/PeopleDeckView.swift` | The people deck + the **It's a match** sheet. |
| `Matches/MatchesListView.swift` | Matches, with "waiting on you" proposals pulled to the top. |
| `Matches/MatchDetailView.swift` | The partial calendar reveal: shared talks, free overlaps, their next planned room, ranked suggestions with **Propose**, incoming proposals with **Accept / Decline** (accepting writes the calendar event), and **Find on radar**. |
| `Matches/MeetupsAPI.swift` | `GET /meetups?pid=` and `PATCH /meetups/:id {status, pid}` — the two calls `Core/APIClient.swift` doesn't have yet, as an extension so Jenish's file stays untouched. Also `MeetupBook`, which makes propose → accept work in stub mode. |

## How to work on it

- **Stub mode is on by default**, so every screen runs with no backend: `Core/Stubs/*.json`.
  In stub mode a right swipe on a person always matches, which is how to rehearse step 4 → 5.
- Switch to the live backend from the **gear icon** → set the base URL → turn off "Use stub data".
- On the onboarding screen, **"Use the demo profile"** skips straight to the tabs.
- The signed-in pid is `appState.profile?.pid`. `appState.selectedTab = .calendar` moves tabs;
  `appState.findOnRadar(pid:)` opens Affinity focused on someone.

## Two things for Jenish, when there's a minute

1. `GET /meet` also returns a `meetups` array (the ones between those two people) and `Meetup`
   has a `label`. `MeetView`/`Meetup` in `Models.swift` don't decode either — harmless, extra
   keys are ignored, but adding them would let `MatchDetailView` drop its second request.
2. `MeetupUpdate` sends only `status`; the backend wants `pid` too, since only the invited
   person may accept. `MeetupsAPI.swift` works around it. If you add `pid` to `MeetupUpdate`,
   `respondToMeetup` can be deleted.

## Cut order (from PLAN.md), for these screens

Propose/accept is cut #3 — if it's late, the suggestion cards still read fine without the
button. Keep the spine: **swipe talks → calendar → swipe people → match → where we can meet.**
