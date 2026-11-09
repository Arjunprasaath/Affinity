import fs from "node:fs";
import path from "node:path";
import { config } from "./config";
import { CONFERENCE_DAYS, SLOTS, iso } from "./time";
import type { Profile, Talk } from "./types";

function readJson<T>(file: string): T {
  return JSON.parse(fs.readFileSync(path.join(config.dataDir, file), "utf8")) as T;
}

interface RawTalk extends Omit<Talk, "start" | "end"> {
  day: number;
  slot: number;
}

export function loadTalks(): Talk[] {
  const { talks } = readJson<{ talks: RawTalk[] }>("talks.json");
  return talks.map(({ day, slot, ...t }) => {
    const date = CONFERENCE_DAYS[day - 1];
    const [s, e] = SLOTS[slot];
    return { ...t, start: iso(date, s), end: iso(date, e) };
  });
}

export interface Persona extends Omit<Profile, "hide_next_room" | "is_persona" | "evidence" | "summary"> {
  saved: string[];
}

export function loadPersonas(): Persona[] {
  return readJson<{ personas: Persona[] }>("personas.json").personas;
}

let places: { places: Record<string, string>; default: string } | null = null;
export function placeNear(room: string | undefined): string {
  if (!places) places = readJson("places.json");
  return (room && places!.places[room]) || places!.default;
}
