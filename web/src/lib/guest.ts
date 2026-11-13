import type { Bundle, ChecklistItem, Expense, Member, NewTripInput, Place, Reservation, Settlement, Trip, TripDay } from "../types";
import type { WandererApi } from "./api";
import { addDays, dateOnly, dayCount, estimatedTimezone, isoFromZoned, rangeDays } from "./dates";

export const GUEST_KEY = "wanderer.guestTrips.v1";
export const GUEST_IMPORTED_KEY = "wanderer.guestImported.v1";
export const GUEST_OWNER_ID = "guest-owner";
export const GUEST_MEMBER: Member = {
  trip_id: "guest",
  user_id: GUEST_OWNER_ID,
  role: "owner",
  profile_id: GUEST_OWNER_ID,
  display_name: "You",
  email: null,
};

function makeId(): string {
  return crypto.randomUUID();
}

function emptyBundle(trip: Trip, days: TripDay[]): Bundle {
  return {
    trip,
    days,
    places: [],
    lists: [],
    reservations: [],
    expenses: [],
    expense_splits: [],
    settlements: [],
    checklist: [],
    members: [{ ...GUEST_MEMBER, trip_id: trip.id }],
    personal: { overrides: [], private_places: [], private_reservations: [] },
  };
}

export function isGuestTripId(id: string | undefined | null): boolean {
  return Boolean(id?.startsWith("guest-"));
}

export function loadGuestBundles(): Bundle[] {
  try {
    const raw = localStorage.getItem(GUEST_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw) as unknown;
    if (!Array.isArray(parsed)) return [];
    return parsed
      .filter((item): item is Bundle => Boolean(item && typeof item === "object" && "trip" in item))
      .map((bundle) => ({
        ...bundle,
        personal: bundle.personal ?? { overrides: [], private_places: [], private_reservations: [] },
        members: bundle.members?.length ? bundle.members : [{ ...GUEST_MEMBER, trip_id: bundle.trip.id }],
      }));
  } catch {
    return [];
  }
}

export function saveGuestBundles(bundles: Bundle[]): void {
  try {
    localStorage.setItem(GUEST_KEY, JSON.stringify(bundles));
  } catch {
    // Storage can be unavailable (private mode/quota). The session still works in memory.
  }
}

export function saveGuestBundle(bundle: Bundle): void {
  const bundles = loadGuestBundles().filter((item) => item.trip.id !== bundle.trip.id);
  bundles.unshift(bundle);
  saveGuestBundles(bundles);
}

export function guestBundle(id: string): Bundle | null {
  return loadGuestBundles().find((bundle) => bundle.trip.id === id) ?? null;
}

export function guestTrips(): Trip[] {
  return loadGuestBundles().map((bundle) => ({
    ...bundle.trip,
    place_count: bundle.places.length + bundle.personal.private_places.length,
  }));
}

export function createGuestTrip(input: NewTripInput): Bundle {
  const id = `guest-${makeId()}`;
  const now = new Date().toISOString();
  const timezone = input.timezone || estimatedTimezone();
  const trip: Trip = {
    id,
    owner_id: GUEST_OWNER_ID,
    title: input.title.trim() || "Untitled trip",
    destination: input.destination.trim() || null,
    start_date: input.start_date || null,
    end_date: input.end_date || null,
    currency: input.currency || "USD",
    cover_url: null,
    cover_color: null,
    notes: null,
    timezone,
    share_token: null,
    created_at: now,
    updated_at: now,
    place_count: 0,
  };
  const dates = input.start_date && input.end_date ? rangeDays(input.start_date, input.end_date) : [];
  const days: TripDay[] = dates.map((date, index) => ({
    id: makeId(),
    trip_id: id,
    day_index: index,
    date,
    title: index === 0 ? "Arrival" : null,
    notes: null,
  }));
  const bundle = emptyBundle(trip, days);
  saveGuestBundle(bundle);
  return bundle;
}

export function updateGuestTrip(id: string, patch: Partial<Trip>): Bundle | null {
  const bundle = guestBundle(id);
  if (!bundle) return null;
  bundle.trip = { ...bundle.trip, ...patch, updated_at: new Date().toISOString() };
  if (patch.start_date || patch.end_date) {
    syncGuestDays(bundle);
  }
  saveGuestBundle(bundle);
  return bundle;
}

export function deleteGuestTrip(id: string): void {
  saveGuestBundles(loadGuestBundles().filter((bundle) => bundle.trip.id !== id));
}

function syncGuestDays(bundle: Bundle): void {
  const { start_date, end_date } = bundle.trip;
  if (!start_date || !end_date) return;
  const count = dayCount(start_date, end_date);
  if (!count) return;
  const existing = [...bundle.days].sort((a, b) => a.day_index - b.day_index);
  const next: TripDay[] = [];
  for (let index = 0; index < count; index += 1) {
    const date = addDays(start_date, index);
    const day = existing.find((item) => item.day_index === index);
    next.push(
      day
        ? { ...day, date }
        : { id: makeId(), trip_id: bundle.trip.id, day_index: index, date, title: null, notes: null },
    );
  }
  const keepIds = new Set(next.map((day) => day.id));
  for (const place of bundle.places) {
    if (place.day_id && !keepIds.has(place.day_id)) place.day_id = null;
  }
  bundle.days = next;
}

export function mutateGuestBundle(id: string, mutate: (bundle: Bundle) => void): Bundle | null {
  const bundle = guestBundle(id);
  if (!bundle) return null;
  mutate(bundle);
  bundle.trip.place_count = bundle.places.length + bundle.personal.private_places.length;
  saveGuestBundle(bundle);
  return bundle;
}

export function makeGuestPlace(tripId: string, values: Partial<Place>, index: number): Place {
  return {
    id: makeId(),
    trip_id: tripId,
    day_id: values.day_id ?? null,
    list_id: values.list_id ?? null,
    name: values.name ?? "Untitled stop",
    address: values.address ?? null,
    lat: values.lat ?? null,
    lng: values.lng ?? null,
    category: values.category ?? "sight",
    notes: values.notes ?? null,
    website: values.website ?? null,
    phone: values.phone ?? null,
    price_level: values.price_level ?? null,
    rating: values.rating ?? null,
    photo_url: values.photo_url ?? null,
    start_time: values.start_time ?? null,
    end_time: values.end_time ?? null,
    position: values.position ?? index,
    visited_at: values.visited_at ?? null,
    created_at: new Date().toISOString(),
  };
}

export function makeGuestReservation(tripId: string, values: Partial<Reservation>): Reservation {
  return {
    id: makeId(),
    trip_id: tripId,
    type: values.type ?? "other",
    title: values.title ?? "Booking",
    provider: values.provider ?? null,
    confirmation_code: values.confirmation_code ?? null,
    start_at: values.start_at ?? null,
    end_at: values.end_at ?? null,
    start_location: values.start_location ?? null,
    end_location: values.end_location ?? null,
    cost: values.cost ?? null,
    currency: values.currency ?? null,
    notes: values.notes ?? null,
    metadata: values.metadata ?? {},
    created_at: new Date().toISOString(),
  };
}

export function makeGuestExpense(tripId: string, values: Partial<Expense>, splits: Bundle["expense_splits"] = []): Expense {
  return {
    id: makeId(),
    trip_id: tripId,
    title: values.title ?? "Expense",
    amount: values.amount ?? 0,
    currency: values.currency ?? "USD",
    category: values.category ?? "other",
    paid_by: values.paid_by ?? null,
    split_with: values.split_with ?? [],
    split_mode: values.split_mode ?? "equal",
    spent_at: values.spent_at ?? dateOnly(new Date()),
    notes: values.notes ?? null,
    place_id: values.place_id ?? null,
    created_at: new Date().toISOString(),
  };
}

export function makeGuestChecklist(tripId: string, title: string, position: number): ChecklistItem {
  return {
    id: makeId(),
    trip_id: tripId,
    title,
    is_checked: false,
    position,
    created_at: new Date().toISOString(),
  };
}

export function makeGuestSettlement(tripId: string, values: Partial<Settlement>): Settlement {
  return {
    id: makeId(),
    trip_id: tripId,
    from_user: values.from_user ?? GUEST_OWNER_ID,
    to_user: values.to_user ?? GUEST_OWNER_ID,
    amount: values.amount ?? 0,
    currency: values.currency ?? "USD",
    settled_at: values.settled_at ?? new Date().toISOString(),
    note: values.note ?? null,
    created_at: new Date().toISOString(),
  };
}

/**
 * Copies guest trips into the signed-in account once. Best effort throughout:
 * a failure leaves the local copy in place and never blocks sign-in.
 */
export async function migrateGuestTrips(api: WandererApi): Promise<{ imported: number; failed: number }> {
  const bundles = loadGuestBundles();
  if (!bundles.length) return { imported: 0, failed: 0 };
  let imported = 0;
  let failed = 0;
  let meId: string | null = null;
  try {
    meId = (await api.me()).id;
  } catch {
    return { imported: 0, failed: bundles.length };
  }

  for (const bundle of bundles) {
    try {
      const created = await api.createTrip({
        title: bundle.trip.title,
        destination: bundle.trip.destination ?? "",
        start_date: bundle.trip.start_date ?? "",
        end_date: bundle.trip.end_date ?? "",
        currency: bundle.trip.currency,
        timezone: bundle.trip.timezone,
      });
      const remote = await api.bundle(created.id);
      const dayByIndex = new Map(remote.days.map((day) => [day.day_index, day.id]));
      const localDayIndex = new Map(bundle.days.map((day) => [day.id, day.day_index]));

      if (bundle.places.length) {
        const places = [...bundle.places]
          .sort((a, b) => a.position - b.position)
          .map((place) => ({
            name: place.name,
            address: place.address,
            lat: place.lat,
            lng: place.lng,
            category: place.category,
            notes: place.notes,
            website: place.website,
            phone: place.phone,
            price_level: place.price_level,
            rating: place.rating,
            photo_url: place.photo_url,
            start_time: place.start_time,
            end_time: place.end_time,
            position: place.position,
            visited_at: place.visited_at,
            day_id: place.day_id ? dayByIndex.get(localDayIndex.get(place.day_id) ?? -1) ?? null : null,
          }))
          .filter((place) => place.name.trim().length > 0);
        if (places.length) {
          await api.addPlace(created.id, places[0]);
          for (const place of places.slice(1)) await api.addPlace(created.id, place);
        }
      }

      for (const reservation of bundle.reservations) {
        await api.addReservation(created.id, {
          type: reservation.type,
          title: reservation.title,
          provider: reservation.provider,
          confirmation_code: reservation.confirmation_code,
          start_at: reservation.start_at,
          end_at: reservation.end_at,
          start_location: reservation.start_location,
          end_location: reservation.end_location,
          cost: reservation.cost,
          currency: reservation.currency,
          notes: reservation.notes,
          metadata: (reservation.metadata ?? {}) as Record<string, unknown>,
        });
      }

      for (const expense of bundle.expenses) {
        const splits = expense.split_with.map((userId) => ({
          user_id: userId === GUEST_OWNER_ID ? meId : userId,
          amount: expense.split_with.length ? expense.amount / expense.split_with.length : expense.amount,
        }));
        await api.addExpense(created.id, {
          title: expense.title,
          amount: expense.amount,
          currency: expense.currency,
          category: expense.category,
          paid_by: expense.paid_by === GUEST_OWNER_ID ? meId : expense.paid_by,
          split_with: expense.split_with.map((userId) => (userId === GUEST_OWNER_ID ? meId : userId)),
          split_mode: expense.split_mode,
          spent_at: expense.spent_at,
          notes: expense.notes,
          splits,
        });
      }

      for (const item of bundle.checklist) {
        const added = await api.addChecklistItem(created.id, item.title, item.position);
        if (item.is_checked) await api.updateChecklistItem(created.id, added.id, { is_checked: true });
      }

      for (const settlement of bundle.settlements) {
        await api.addSettlement(created.id, {
          from_user: settlement.from_user === GUEST_OWNER_ID ? meId : settlement.from_user,
          to_user: settlement.to_user === GUEST_OWNER_ID ? meId : settlement.to_user,
          amount: settlement.amount,
          currency: settlement.currency,
          settled_at: settlement.settled_at,
          note: settlement.note,
        });
      }

      imported += 1;
      saveGuestBundles(loadGuestBundles().filter((item) => item.trip.id !== bundle.trip.id));
    } catch {
      failed += 1;
    }
  }
  if (!failed) localStorage.setItem(GUEST_IMPORTED_KEY, new Date().toISOString());
  return { imported, failed };
}

export function guestTripDayForDate(bundle: Bundle, date: string): TripDay | null {
  return bundle.days.find((day) => day.date === date) ?? null;
}

export function guestNowStamp(): string {
  return isoFromZoned(dateOnly(new Date()), "12:00", estimatedTimezone());
}
