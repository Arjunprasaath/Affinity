// backend/src/talks.ts
// STUB: returns the sample from the API contract. Arjun replaces the body.
// Skip this file if Arjun has already pushed his own talks.ts.

export interface SharedTalk {
  id: string;
  title: string;
  room: string;
  start: string;
  why: string;
}

export async function sharedTalks(a: string, b: string): Promise<SharedTalk[]> {
  return [
    {
      id: "t_42",
      title: "eBPF at Scale",
      room: "Room 155",
      start: "2026-11-10T15:30:00-07:00",
      why: "Both of you work on Cilium",
    },
  ];
}
