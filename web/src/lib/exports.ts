import type { Bundle, Place, Reservation, Trip } from "../types";
import { dateKeyInZone } from "./dates";

function escapeIcs(value: string): string {
  return value.replace(/\\/g, "\\\\").replace(/\n/g, "\\n").replace(/,/g, "\\,").replace(/;/g, "\;");
}

function utcStamp(value: string | Date): string {
  const date = value instanceof Date ? value : new Date(value);
  if (!Number.isFinite(date.getTime())) return "19700101T000000Z";
  return date.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
}

function dateStamp(value: string): string {
  return value.replace(/-/g, "");
}

export function calendarFile(trip: Trip, places: Place[], reservations: Reservation[]): string {
  const lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Wanderer//Trip//EN",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    `X-WR-CALNAME:${escapeIcs(trip.title)}`,
  ];
  const stamp = utcStamp(new Date());

  for (const reservation of reservations) {
    if (!reservation.start_at) continue;
    const start = new Date(reservation.start_at);
    if (!Number.isFinite(start.getTime())) continue;
    const end = reservation.end_at && Number.isFinite(new Date(reservation.end_at).getTime())
      ? new Date(reservation.end_at)
      : new Date(start.getTime() + 2 * 3600 * 1000);
    lines.push("BEGIN:VEVENT");
    lines.push(`UID:reservation-${reservation.id}@wanderer`);
    lines.push(`DTSTAMP:${stamp}`);
    lines.push(`DTSTART:${utcStamp(start)}`);
    lines.push(`DTEND:${utcStamp(end)}`);
    lines.push(`SUMMARY:${escapeIcs(`${reservation.type}: ${reservation.title}`)}`);
    const location = reservation.start_location ?? reservation.end_location;
    if (location) lines.push(`LOCATION:${escapeIcs(location)}`);
    const description = [reservation.provider, reservation.confirmation_code, reservation.notes]
      .map((value) => value?.trim())
      .filter((value): value is string => Boolean(value))
      .join("\n") || "Added in Wanderer";
    lines.push(`DESCRIPTION:${escapeIcs(description)}`);
    lines.push("END:VEVENT");
  }

  const dayById = new Map(places.map((place) => [place.id, place]));
  for (const place of places) {
    if (place.start_time) {
      const start = new Date(place.start_time);
      if (!Number.isFinite(start.getTime())) continue;
      const end = place.end_time && Number.isFinite(new Date(place.end_time).getTime())
        ? new Date(place.end_time)
        : new Date(start.getTime() + 3600 * 1000);
      lines.push("BEGIN:VEVENT");
      lines.push(`UID:place-${place.id}@wanderer`);
      lines.push(`DTSTAMP:${stamp}`);
      lines.push(`DTSTART:${utcStamp(start)}`);
      lines.push(`DTEND:${utcStamp(end)}`);
      lines.push(`SUMMARY:${escapeIcs(place.name)}`);
      if (place.address) lines.push(`LOCATION:${escapeIcs(place.address)}`);
      const description = [place.category, place.notes]
        .filter((value): value is string => Boolean(value))
        .join("\n") || "Planned in Wanderer";
      lines.push(`DESCRIPTION:${escapeIcs(description)}`);
      lines.push("END:VEVENT");
    } else {
      const bundleDay = dayById.get(place.id);
      void bundleDay;
    }
  }

  lines.push("END:VCALENDAR");
  return `${lines.join("\r\n")}\r\n`;
}

export function calendarFileForBundle(bundle: Bundle): string {
  const lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Wanderer//Trip//EN",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    `X-WR-CALNAME:${escapeIcs(bundle.trip.title)}`,
  ];
  const stamp = utcStamp(new Date());
  const dayDate = new Map(bundle.days.map((day) => [day.id, day.date]));

  for (const reservation of bundle.reservations) {
    if (!reservation.start_at) continue;
    const start = new Date(reservation.start_at);
    if (!Number.isFinite(start.getTime())) continue;
    const end = reservation.end_at && Number.isFinite(new Date(reservation.end_at).getTime())
      ? new Date(reservation.end_at)
      : new Date(start.getTime() + 2 * 3600 * 1000);
    lines.push("BEGIN:VEVENT");
    lines.push(`UID:reservation-${reservation.id}@wanderer`);
    lines.push(`DTSTAMP:${stamp}`);
    lines.push(`DTSTART:${utcStamp(start)}`);
    lines.push(`DTEND:${utcStamp(end)}`);
    lines.push(`SUMMARY:${escapeIcs(`${reservation.type}: ${reservation.title}`)}`);
    const location = reservation.start_location ?? reservation.end_location;
    if (location) lines.push(`LOCATION:${escapeIcs(location)}`);
    const description = [reservation.provider, reservation.confirmation_code, reservation.notes]
      .map((value) => value?.trim())
      .filter((value): value is string => Boolean(value))
      .join("\n") || "Added in Wanderer";
    lines.push(`DESCRIPTION:${escapeIcs(description)}`);
    lines.push("END:VEVENT");
  }

  for (const place of bundle.places) {
    if (place.start_time) {
      const start = new Date(place.start_time);
      if (!Number.isFinite(start.getTime())) continue;
      const end = place.end_time && Number.isFinite(new Date(place.end_time).getTime())
        ? new Date(place.end_time)
        : new Date(start.getTime() + 3600 * 1000);
      lines.push("BEGIN:VEVENT");
      lines.push(`UID:place-${place.id}@wanderer`);
      lines.push(`DTSTAMP:${stamp}`);
      lines.push(`DTSTART:${utcStamp(start)}`);
      lines.push(`DTEND:${utcStamp(end)}`);
      lines.push(`SUMMARY:${escapeIcs(place.name)}`);
      if (place.address) lines.push(`LOCATION:${escapeIcs(place.address)}`);
      const description = [place.category, place.notes]
        .filter((value): value is string => Boolean(value))
        .join("\n") || "Planned in Wanderer";
      lines.push(`DESCRIPTION:${escapeIcs(description)}`);
      lines.push("END:VEVENT");
    } else if (place.day_id) {
      const date = dayDate.get(place.day_id);
      if (!date) continue;
      lines.push("BEGIN:VEVENT");
      lines.push(`UID:place-${place.id}@wanderer`);
      lines.push(`DTSTAMP:${stamp}`);
      lines.push(`DTSTART;VALUE=DATE:${dateStamp(date)}`);
      const next = new Date(`${date}T00:00:00Z`);
      next.setUTCDate(next.getUTCDate() + 1);
      lines.push(`DTEND;VALUE=DATE:${dateStamp(next.toISOString().slice(0, 10))}`);
      lines.push(`SUMMARY:${escapeIcs(place.name)}`);
      if (place.address) lines.push(`LOCATION:${escapeIcs(place.address)}`);
      if (place.notes) lines.push(`DESCRIPTION:${escapeIcs(place.notes)}`);
      lines.push("END:VEVENT");
    }
  }
  void dateKeyInZone;
  lines.push("END:VCALENDAR");
  return `${lines.join("\r\n")}\r\n`;
}

export function downloadText(filename: string, text: string, type = "text/calendar;charset=utf-8"): void {
  const blob = new Blob([text], { type });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 1000);
}

export function googleMapsUrl(places: Place[], mode: "walking" | "driving" = "walking"): string | null {
  const coordinates = places
    .filter((place) => Number.isFinite(place.lat) && Number.isFinite(place.lng))
    .map((place) => `${place.lat},${place.lng}`);
  if (coordinates.length < 2) return null;
  const chunk = coordinates.slice(0, 10);
  const origin = chunk[0];
  const destination = chunk[chunk.length - 1];
  const waypoints = chunk.slice(1, -1).join("|");
  const params = new URLSearchParams({ api: "1", travelmode: mode, origin, destination });
  if (waypoints) params.set("waypoints", waypoints);
  return `https://www.google.com/maps/dir/?${params.toString()}`;
}
