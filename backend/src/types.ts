export type Status = "green" | "yellow" | "red";
export type SwipeDir = "right" | "up" | "left";
export type TargetType = "talk" | "person";

export interface Evidence {
  topic: string;
  source: string;
}

export interface Profile {
  pid: string;
  name: string;
  role?: string;
  company?: string;
  pronouns?: string;
  github?: string;
  linkedin?: string;
  working_on: string;
  looking_for: string;
  offering: string;
  here_for: string[];
  topics: string[];
  summary?: string;
  evidence?: Evidence[];
  status: Status;
  hide_next_room: boolean;
  is_persona?: boolean;
  created_at?: string;
}

export interface Talk {
  tid: string;
  title: string;
  abstract: string;
  speakers: string[];
  room: string;
  start: string; // ISO with -07:00 offset
  end: string;
  level: "beginner" | "intermediate" | "advanced";
  track: string;
  topics: string[];
}

export interface TalkCard extends Omit<Talk, "abstract"> {
  abstract: string;
  reason: string;
  clashes_with: { tid: string; title: string } | null;
}

export interface ScheduleItem {
  tid: string;
  title: string;
  room: string;
  start: string;
  end: string;
  must: boolean;
  clash: boolean;
}

export interface TimeBlock {
  start: string;
  end: string;
}

export interface Schedule {
  pid: string;
  items: ScheduleItem[];
  free: TimeBlock[];
}

export interface PersonCard {
  pid: string;
  name: string;
  role?: string;
  company?: string;
  pronouns?: string;
  working_on: string;
  here_for: string[];
  topics: string[];
  shared_topics: string[];
  shared_talks_count: number;
  score: number;
  reason: string;
  status: Status;
  github?: string;
}

export interface Match {
  pid: string;
  name: string;
  role?: string;
  company?: string;
  matched_at: string;
  reason: string;
}

export interface Meetup {
  id: string;
  a: string; // proposer
  b: string;
  place: string;
  start: string;
  end: string;
  label?: string;
  status: "proposed" | "accepted" | "declined";
  created_at: string;
}
