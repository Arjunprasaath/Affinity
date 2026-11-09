import { randomBytes } from "node:crypto";
import { es, IDX, getDoc, searchAll } from "./elastic";
import { badRequest, forbidden, notFound } from "./errors";
import { getMatchDoc } from "./matches";
import type { Meetup } from "./types";

type MeetupDoc = Meetup & { pids: string[] };

export async function proposeMeetup(input: Partial<Meetup>): Promise<Meetup> {
  const { a, b, place, start, end, label } = input;
  if (!a || !b || !place || !start || !end) throw badRequest("a, b, place, start and end are required");
  if (Number.isNaN(Date.parse(start)) || Number.isNaN(Date.parse(end)) || Date.parse(end) <= Date.parse(start)) {
    throw badRequest("start and end must be ISO times with end after start");
  }
  if (!(await getMatchDoc(a, b))) throw forbidden("you can only propose meetups to mutual matches");
  const m: MeetupDoc = {
    id: "m_" + randomBytes(4).toString("hex"),
    a,
    b,
    pids: [a, b],
    place,
    start,
    end,
    label,
    status: "proposed",
    created_at: new Date().toISOString(),
  };
  await es().index({ index: IDX.meetups, id: m.id, document: m, refresh: true });
  return strip(m);
}

export async function updateMeetup(id: string, status: string, pid?: string): Promise<Meetup> {
  if (!["accepted", "declined"].includes(status)) throw badRequest("status must be accepted or declined");
  const m = await getDoc<MeetupDoc>(IDX.meetups, id);
  if (!m) throw notFound(`meetup ${id}`);
  if (pid && pid !== m.b) throw forbidden("only the invited person can accept or decline");
  await es().update({ index: IDX.meetups, id, doc: { status }, refresh: true });
  return strip({ ...m, status: status as Meetup["status"] });
}

export async function meetupsFor(pid: string): Promise<Meetup[]> {
  const docs = await searchAll<MeetupDoc>(IDX.meetups, { term: { pids: pid } }, 500);
  return docs.map(strip).sort((x, y) => Date.parse(x.start) - Date.parse(y.start));
}

export async function meetupsBetween(a: string, b: string): Promise<Meetup[]> {
  return (await meetupsFor(a)).filter((m) => m.a === b || m.b === b);
}

export async function acceptedMeetupsFor(pid: string): Promise<Meetup[]> {
  return (await meetupsFor(pid)).filter((m) => m.status === "accepted");
}

function strip(m: MeetupDoc): Meetup {
  const { pids, ...rest } = m;
  return rest;
}
