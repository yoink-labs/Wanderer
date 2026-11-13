import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useSession } from "../auth/session";
import { dateKeyInZone, isoFromZoned } from "../lib/dates";
import {
  deleteGuestTrip,
  guestBundle,
  isGuestTripId,
  makeGuestChecklist,
  makeGuestExpense,
  makeGuestPlace,
  makeGuestReservation,
  makeGuestSettlement,
  mutateGuestBundle,
  saveGuestBundle,
  updateGuestTrip,
} from "../lib/guest";
import type {
  Bundle,
  ChecklistItem,
  ExpenseInput,
  FlightsEnvelope,
  Member,
  PersonalOverride,
  Place,
  PlaceInput,
  Profile,
  Reservation,
  ReservationInput,
  TripRole,
} from "../types";
import { ApiRequestError } from "../lib/api";

const CACHE_PREFIX = "wanderer.tripCache.v1";
const RECENT_KEY = "wanderer.recentTrips";

interface CachedBundle {
  bundle: Bundle;
  savedAt: string;
}

function cacheKey(tripId: string, email: string | null | undefined): string {
  const owner = (email ?? "local").toLowerCase().replace(/[^a-z0-9@._-]/g, "");
  return `${CACHE_PREFIX}.${owner}.${tripId}`;
}

function readCache(tripId: string, email: string | null | undefined): CachedBundle | null {
  try {
    const raw = localStorage.getItem(cacheKey(tripId, email));
    if (!raw) return null;
    const parsed = JSON.parse(raw) as CachedBundle;
    if (!parsed.bundle?.trip) return null;
    return parsed;
  } catch {
    return null;
  }
}

function writeCache(tripId: string, email: string | null | undefined, bundle: Bundle): string {
  const savedAt = new Date().toISOString();
  try {
    localStorage.setItem(cacheKey(tripId, email), JSON.stringify({ bundle, savedAt } satisfies CachedBundle));
  } catch {
    // Cache is best effort.
  }
  return savedAt;
}

function recordRecent(tripId: string): void {
  try {
    const current = JSON.parse(localStorage.getItem(RECENT_KEY) || "[]") as unknown;
    const ids = Array.isArray(current)
      ? current.filter((value): value is string => typeof value === "string" && value !== tripId)
      : [];
    ids.unshift(tripId);
    localStorage.setItem(RECENT_KEY, JSON.stringify(ids.slice(0, 8)));
  } catch {
    // ignore
  }
}

function isNetworkError(error: unknown): boolean {
  return error instanceof ApiRequestError && (error.code === "offline" || error.status === 0);
}

function dayIndexById(bundle: Bundle): Map<string, number> {
  return new Map(bundle.days.map((day) => [day.id, day.day_index]));
}

export function sortPlaces(places: Place[], bundle: Bundle): Place[] {
  const dayOrder = dayIndexById(bundle);
  return [...places].sort((a, b) => {
    const aDay = a.day_id ? dayOrder.get(a.day_id) ?? Number.MAX_SAFE_INTEGER : Number.MAX_SAFE_INTEGER;
    const bDay = b.day_id ? dayOrder.get(b.day_id) ?? Number.MAX_SAFE_INTEGER : Number.MAX_SAFE_INTEGER;
    if (aDay !== bDay) return aDay - bDay;
    if (a.position !== b.position) return a.position - b.position;
    return a.name.localeCompare(b.name);
  });
}

function applyPlaceOverride(place: Place, overrides: PersonalOverride[]): { place: Place; hidden: boolean; overridden: boolean } {
  const override = overrides.find((item) => item.item_type === "place" && item.item_id === place.id);
  if (!override) return { place, hidden: false, overridden: false };
  const data = (override.data ?? {}) as Partial<Place>;
  return {
    place: { ...place, ...data, id: place.id, trip_id: place.trip_id, _overridden: Object.keys(data).length > 0 },
    hidden: Boolean(override.hidden),
    overridden: Object.keys(data).length > 0,
  };
}

function applyReservationOverride(
  reservation: Reservation,
  overrides: PersonalOverride[],
): { reservation: Reservation; hidden: boolean; overridden: boolean } {
  const override = overrides.find((item) => item.item_type === "reservation" && item.item_id === reservation.id);
  if (!override) return { reservation, hidden: false, overridden: false };
  const data = (override.data ?? {}) as Partial<Reservation>;
  let metadata = reservation.metadata;
  if (data.metadata) {
    metadata = typeof data.metadata === "string" ? safeMetadata(data.metadata) : (data.metadata as Record<string, unknown>);
  }
  return {
    reservation: {
      ...reservation,
      ...data,
      metadata,
      id: reservation.id,
      trip_id: reservation.trip_id,
      _overridden: Object.keys(data).length > 0,
    },
    hidden: Boolean(override.hidden),
    overridden: Object.keys(data).length > 0,
  };
}

function safeMetadata(value: string): Record<string, unknown> {
  try {
    const parsed = JSON.parse(value) as unknown;
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? (parsed as Record<string, unknown>) : {};
  } catch {
    return {};
  }
}

function cleanPlaceOverride(patch: Partial<PlaceInput>): Record<string, unknown> {
  const allowed = [
    "name", "address", "lat", "lng", "category", "notes", "website", "phone",
    "start_time", "end_time", "photo_url", "rating", "price_level", "day_id", "position",
  ];
  return Object.fromEntries(Object.entries(patch).filter(([key, value]) => allowed.includes(key) && value !== undefined));
}

function cleanReservationOverride(patch: Partial<ReservationInput>): Record<string, unknown> {
  const allowed = [
    "type", "title", "provider", "confirmation_code", "start_at", "end_at",
    "start_location", "end_location", "cost", "currency", "notes", "metadata",
  ];
  return Object.fromEntries(Object.entries(patch).filter(([key, value]) => allowed.includes(key) && value !== undefined));
}

export interface TripStore {
  tripId: string;
  isGuest: boolean;
  bundle: Bundle | null;
  loading: boolean;
  error: string | null;
  offline: boolean;
  savedOfflineAt: string | null;
  canWrite: boolean;
  role: TripRole | null;
  profile: Profile | null;
  currentUserId: string | null;
  currentMember: Member | null;
  flights: FlightsEnvelope | null;
  flightsError: string | null;
  flightsLoading: boolean;
  places: Place[];
  reservations: Reservation[];
  hiddenPlaces: Place[];
  hiddenReservations: Reservation[];
  privatePlaces: Place[];
  privateReservations: Reservation[];
  overriddenPlaces: Place[];
  overriddenReservations: Reservation[];
  reload: () => Promise<void>;
  refreshFlights: () => Promise<void>;
  updateTrip: (patch: Partial<Bundle["trip"]>) => Promise<void>;
  deleteTrip: () => Promise<void>;
  updateDayNotes: (dayId: string, notes: string) => Promise<void>;
  addPlace: (input: PlaceInput, personal?: boolean) => Promise<void>;
  updatePlace: (place: Place, patch: Partial<PlaceInput>, mode?: "shared" | "personal" | "override") => Promise<void>;
  deletePlace: (place: Place, mode?: "shared" | "personal") => Promise<void>;
  setVisited: (place: Place, visited: boolean) => Promise<void>;
  movePlace: (place: Place, direction: "up" | "down") => Promise<void>;
  movePlaceToDay: (place: Place, dayId: string | null) => Promise<void>;
  addReservation: (input: ReservationInput, personal?: boolean) => Promise<void>;
  updateReservation: (reservation: Reservation, patch: Partial<ReservationInput>, mode?: "shared" | "personal" | "override") => Promise<void>;
  deleteReservation: (reservation: Reservation, mode?: "shared" | "personal") => Promise<void>;
  hidePersonal: (itemType: "place" | "reservation", itemId: string, hidden: boolean) => Promise<void>;
  savePersonalVersion: (itemType: "place" | "reservation", itemId: string, data: Record<string, unknown>) => Promise<void>;
  restorePersonal: (itemType: "place" | "reservation", itemId: string) => Promise<void>;
  addExpense: (input: ExpenseInput) => Promise<void>;
  deleteExpense: (id: string) => Promise<void>;
  addSettlement: (input: { from_user: string; to_user: string; amount: number; currency: string; settled_at?: string; note?: string | null }) => Promise<void>;
  addChecklistItem: (title: string) => Promise<void>;
  setChecklistChecked: (item: ChecklistItem, checked: boolean) => Promise<void>;
  deleteChecklistItem: (id: string) => Promise<void>;
}

export function useTripStore(tripId: string): TripStore {
  const session = useSession();
  const isGuest = isGuestTripId(tripId);
  const [bundle, setBundle] = useState<Bundle | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [offline, setOffline] = useState(false);
  const [savedOfflineAt, setSavedOfflineAt] = useState<string | null>(null);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [flights, setFlights] = useState<FlightsEnvelope | null>(null);
  const [flightsError, setFlightsError] = useState<string | null>(null);
  const [flightsLoading, setFlightsLoading] = useState(false);
  const mounted = useRef(true);
  const loadingFlights = useRef(false);

  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
    };
  }, []);

  const loadFlights = useCallback(async () => {
    if (isGuest || !session.isSignedIn) {
      setFlights(null);
      return;
    }
    if (loadingFlights.current) return;
    loadingFlights.current = true;
    setFlightsLoading(true);
    setFlightsError(null);
    try {
      const envelope = await session.api.flights(tripId);
      if (mounted.current) setFlights(envelope);
    } catch (caught) {
      if (mounted.current) {
        setFlightsError(caught instanceof Error ? caught.message : "Live flight status is unavailable.");
      }
    } finally {
      loadingFlights.current = false;
      if (mounted.current) setFlightsLoading(false);
    }
  }, [isGuest, session.api, session.isSignedIn, tripId]);

  const load = useCallback(async () => {
    if (mounted.current) {
      setLoading(true);
      setError(null);
    }
    recordRecent(tripId);

    if (isGuest) {
      const local = guestBundle(tripId);
      if (!local) {
        if (mounted.current) {
          setError("That guest trip isn't on this device anymore.");
          setLoading(false);
        }
        return;
      }
      if (mounted.current) {
        setBundle(local);
        setOffline(false);
        setSavedOfflineAt(localStorage.getItem("wanderer.guestLastSaved") || new Date().toISOString());
        setLoading(false);
      }
      return;
    }

    let profileResult: Profile | null = null;
    try {
      profileResult = await session.api.me();
      if (mounted.current) setProfile(profileResult);
    } catch {
      // The bundle can carry enough for reading; identity only affects permissions.
    }

    try {
      const loaded = await session.api.bundle(tripId);
      if (!mounted.current) return;
      const savedAt = writeCache(tripId, profileResult?.email ?? session.user?.email, loaded);
      setBundle(loaded);
      setSavedOfflineAt(savedAt);
      setOffline(false);
      setError(null);
      setLoading(false);
      void loadFlights();
    } catch (caught) {
      const cached = readCache(tripId, profileResult?.email ?? session.user?.email);
      if (cached && (!(caught instanceof ApiRequestError) || (caught.status !== 401 && caught.status !== 403))) {
        if (!mounted.current) return;
        setBundle(cached.bundle);
        setSavedOfflineAt(cached.savedAt);
        setOffline(true);
        setError(null);
        setLoading(false);
        return;
      }
      if (!mounted.current) return;
      setError(caught instanceof Error ? caught.message : "Couldn't open this trip.");
      setLoading(false);
    }
  }, [isGuest, loadFlights, session.api, session.user?.email, tripId]);

  useEffect(() => {
    void load();
  }, [load]);

  useEffect(() => {
    const goOffline = () => {
      if (!isGuest && bundle) {
        setOffline(true);
      }
    };
    window.addEventListener("offline", goOffline);
    return () => window.removeEventListener("offline", goOffline);
  }, [bundle, isGuest]);

  useEffect(() => {
    if (!bundle?.trip.currency) return;
    localStorage.setItem("wanderer.currency", bundle.trip.currency);
  }, [bundle?.trip.currency]);

  const currentMember = useMemo(() => {
    if (!bundle) return null;
    if (isGuest) return bundle.members[0] ?? null;
    if (!profile) {
      const email = session.user?.email?.toLowerCase();
      if (!email) return null;
      return bundle.members.find((member) => member.email?.toLowerCase() === email) ?? null;
    }
    return (
      bundle.members.find((member) => member.user_id === profile.id || member.profile_id === profile.id) ??
      bundle.members.find((member) => member.email?.toLowerCase() === profile.email?.toLowerCase()) ??
      null
    );
  }, [bundle, isGuest, profile, session.user?.email]);

  const role: TripRole | null = isGuest ? "owner" : currentMember?.role ?? null;
  const canWrite = Boolean(bundle) && !offline && role !== "viewer" && (isGuest || role !== null);
  const currentUserId = isGuest ? (bundle?.members[0]?.user_id ?? null) : (profile?.id ?? currentMember?.user_id ?? null);

  const merged = useMemo(() => {
    if (!bundle) {
      return {
        places: [] as Place[],
        reservations: [] as Reservation[],
        hiddenPlaces: [] as Place[],
        hiddenReservations: [] as Reservation[],
        overriddenPlaces: [] as Place[],
        overriddenReservations: [] as Reservation[],
      };
    }
    const overrides = bundle.personal?.overrides ?? [];
    const places: Place[] = [];
    const hiddenPlaces: Place[] = [];
    const overriddenPlaces: Place[] = [];
    for (const shared of bundle.places) {
      const mergedPlace = applyPlaceOverride(shared, overrides);
      if (mergedPlace.hidden) hiddenPlaces.push({ ...shared, _overridden: mergedPlace.overridden });
      else {
        places.push(mergedPlace.place);
        if (mergedPlace.overridden) overriddenPlaces.push(mergedPlace.place);
      }
    }
    for (const privatePlace of bundle.personal?.private_places ?? []) {
      places.push({ ...privatePlace, _private: true });
    }

    const reservations: Reservation[] = [];
    const hiddenReservations: Reservation[] = [];
    const overriddenReservations: Reservation[] = [];
    for (const shared of bundle.reservations) {
      const mergedReservation = applyReservationOverride(shared, overrides);
      if (mergedReservation.hidden) hiddenReservations.push(shared);
      else {
        reservations.push(mergedReservation.reservation);
        if (mergedReservation.overridden) overriddenReservations.push(mergedReservation.reservation);
      }
    }
    for (const privateReservation of bundle.personal?.private_reservations ?? []) {
      reservations.push({ ...privateReservation, _private: true });
    }
    const sortedPlaces = sortPlaces(places, bundle);
    const sortedReservations = [...reservations].sort((a, b) => (a.start_at ?? "").localeCompare(b.start_at ?? ""));
    return {
      places: sortedPlaces,
      reservations: sortedReservations,
      hiddenPlaces,
      hiddenReservations,
      overriddenPlaces,
      overriddenReservations,
    };
  }, [bundle]);

  const ensureWritable = useCallback(() => {
    if (offline) throw new Error("You're offline. Reconnect to make changes.");
    if (role === "viewer") throw new Error("You have view-only access to this trip.");
  }, [offline, role]);

  const refreshQuietly = useCallback(async () => {
    if (isGuest) {
      const local = guestBundle(tripId);
      if (local && mounted.current) {
        setBundle(local);
        setSavedOfflineAt(new Date().toISOString());
      }
      return;
    }
    try {
      const next = await session.api.bundle(tripId);
      if (!mounted.current) return;
      const savedAt = writeCache(tripId, profile?.email ?? session.user?.email, next);
      setBundle(next);
      setSavedOfflineAt(savedAt);
      setOffline(false);
      setError(null);
    } catch (caught) {
      if (isNetworkError(caught) && mounted.current) setOffline(true);
      throw caught;
    }
  }, [isGuest, profile?.email, session.api, session.user?.email, tripId]);

  const guestMutate = useCallback(
    (mutate: (local: Bundle) => void) => {
      const updated = mutateGuestBundle(tripId, mutate);
      if (!updated) throw new Error("That guest trip isn't on this device anymore.");
      saveGuestBundle(updated);
      localStorage.setItem("wanderer.guestLastSaved", new Date().toISOString());
      setBundle({ ...updated });
      setSavedOfflineAt(localStorage.getItem("wanderer.guestLastSaved"));
    },
    [tripId],
  );

  const afterMutation = useCallback(async () => {
    await refreshQuietly();
  }, [refreshQuietly]);

  const updateTrip = useCallback(
    async (patch: Partial<Bundle["trip"]>) => {
      ensureWritable();
      if (isGuest) {
        const updated = updateGuestTrip(tripId, patch);
        if (!updated) throw new Error("That guest trip isn't on this device anymore.");
        setBundle({ ...updated });
        return;
      }
      await session.api.updateTrip(tripId, patch);
      await afterMutation();
    },
    [afterMutation, ensureWritable, isGuest, session.api, tripId],
  );

  const deleteTrip = useCallback(async () => {
    ensureWritable();
    if (isGuest) {
      deleteGuestTrip(tripId);
      return;
    }
    await session.api.deleteTrip(tripId);
  }, [ensureWritable, isGuest, session.api, tripId]);

  const updateDayNotes = useCallback(
    async (dayId: string, notes: string) => {
      ensureWritable();
      if (isGuest) {
        guestMutate((local) => {
          const day = local.days.find((item) => item.id === dayId);
          if (day) day.notes = notes;
        });
        return;
      }
      await session.api.updateDay(tripId, dayId, { notes });
      await afterMutation();
    },
    [afterMutation, ensureWritable, guestMutate, isGuest, session.api, tripId],
  );

  const addPlace = useCallback(
    async (input: PlaceInput, personal = false) => {
      ensureWritable();
      if (personal && !isGuest) {
        await session.api.addPrivatePlace(tripId, input);
        await afterMutation();
        return;
      }
      if (isGuest) {
        guestMutate((local) => {
          const count = local.places.filter((place) => place.day_id === (input.day_id ?? null)).length;
          local.places.push(makeGuestPlace(local.trip.id, { ...input, position: input.position ?? count }, count));
        });
        return;
      }
      await session.api.addPlace(tripId, input);
      await afterMutation();
    },
    [afterMutation, ensureWritable, guestMutate, isGuest, session.api, tripId],
  );

  const updatePlace = useCallback(
    async (place: Place, patch: Partial<PlaceInput>, mode: "shared" | "personal" | "override" = "shared") => {
      ensureWritable();
      if (isGuest) {
        guestMutate((local) => {
          const target = local.places.find((item) => item.id === place.id);
          if (target) Object.assign(target, patch);
        });
        return;
      }
      if (mode === "personal" || place._private) {
        await session.api.updatePrivatePlace(tripId, place.id, patch);
      } else if (mode === "override") {
        const existing = bundle?.personal.overrides.find((item) => item.item_type === "place" && item.item_id === place.id);
        await session.api.putOverride(tripId, "place", place.id, existing?.hidden ?? false, cleanPlaceOverride(patch));
      } else {
        await session.api.updatePlace(tripId, place.id, patch);
      }
      await afterMutation();
    },
    [afterMutation, bundle?.personal.overrides, ensureWritable, guestMutate, isGuest, session.api, tripId],
  );

  const deletePlace = useCallback(
    async (place: Place, mode: "shared" | "personal" = "shared") => {
      ensureWritable();
      if (isGuest) {
        guestMutate((local) => {
          local.places = local.places.filter((item) => item.id !== place.id);
        });
        return;
      }
      if (mode === "personal" || place._private) {
        await session.api.deletePrivatePlace(tripId, place.id);
      } else {
        await session.api.deletePlace(tripId, place.id);
      }
      await afterMutation();
    },
    [afterMutation, ensureWritable, guestMutate, isGuest, session.api, tripId],
  );

  const setVisited = useCallback(
    async (place: Place, visited: boolean) => {
      ensureWritable();
      const stamp = visited ? new Date().toISOString() : null;
      await updatePlace(place, { visited_at: stamp }, place._private ? "personal" : "shared");
    },
    [ensureWritable, updatePlace],
  );

  const movePlace = useCallback(
    async (place: Place, direction: "up" | "down") => {
      ensureWritable();
      const siblings = merged.places.filter((item) => item.day_id === place.day_id).sort((a, b) => a.position - b.position);
      const index = siblings.findIndex((item) => item.id === place.id);
      const swapIndex = direction === "up" ? index - 1 : index + 1;
      if (index < 0 || swapIndex < 0 || swapIndex >= siblings.length) return;
      const other = siblings[swapIndex];
      if (isGuest) {
        guestMutate((local) => {
          const a = local.places.find((item) => item.id === place.id);
          const b = local.places.find((item) => item.id === other.id);
          if (a && b) {
            const temp = a.position;
            a.position = b.position;
            b.position = temp;
          }
        });
        return;
      }
      const mode = place._private ? "personal" : "shared";
      if (mode === "personal") {
        await Promise.all([
          session.api.updatePrivatePlace(tripId, place.id, { position: other.position }),
          session.api.updatePrivatePlace(tripId, other.id, { position: place.position }),
        ]);
      } else {
        await Promise.all([
          session.api.updatePlace(tripId, place.id, { position: other.position }),
          session.api.updatePlace(tripId, other.id, { position: place.position }),
        ]);
      }
      await afterMutation();
    },
    [afterMutation, ensureWritable, guestMutate, isGuest, merged.places, session.api, tripId],
  );

  const movePlaceToDay = useCallback(
    async (place: Place, dayId: string | null) => {
      ensureWritable();
      const targetDay = bundle?.days.find((day) => day.id === dayId);
      const position = merged.places.filter((item) => item.day_id === dayId).length;
      const patch: Partial<PlaceInput> = { day_id: dayId, position };
      if (place.start_time && targetDay?.date && bundle) {
        const time = new Intl.DateTimeFormat("en-GB", {
          timeZone: bundle.trip.timezone,
          hour: "2-digit",
          minute: "2-digit",
          hourCycle: "h23",
        }).format(new Date(place.start_time));
        patch.start_time = isoFromZoned(targetDay.date, time, bundle.trip.timezone);
        if (place.end_time) {
          const endTime = new Intl.DateTimeFormat("en-GB", {
            timeZone: bundle.trip.timezone,
            hour: "2-digit",
            minute: "2-digit",
            hourCycle: "h23",
          }).format(new Date(place.end_time));
          patch.end_time = isoFromZoned(targetDay.date, endTime, bundle.trip.timezone);
        }
      }
      await updatePlace(place, patch, place._private ? "personal" : "shared");
    },
    [bundle, ensureWritable, merged.places, updatePlace],
  );

  const addReservation = useCallback(
    async (input: ReservationInput, personal = false) => {
      ensureWritable();
      if (personal && !isGuest) {
        await session.api.addPrivateReservation(tripId, input);
        await afterMutation();
        return;
      }
      if (isGuest) {
        guestMutate((local) => {
          local.reservations.push(makeGuestReservation(local.trip.id, input as Partial<Reservation>));
        });
        return;
      }
      await session.api.addReservation(tripId, input);
      await afterMutation();
      void loadFlights();
    },
    [afterMutation, ensureWritable, guestMutate, isGuest, loadFlights, session.api, tripId],
  );

  const updateReservation = useCallback(
    async (reservation: Reservation, patch: Partial<ReservationInput>, mode: "shared" | "personal" | "override" = "shared") => {
      ensureWritable();
      if (isGuest) {
        guestMutate((local) => {
          const target = local.reservations.find((item) => item.id === reservation.id);
          if (target) Object.assign(target, patch);
        });
        return;
      }
      if (mode === "personal" || reservation._private) {
        await session.api.updatePrivateReservation(tripId, reservation.id, patch);
      } else if (mode === "override") {
        const existing = bundle?.personal.overrides.find((item) => item.item_type === "reservation" && item.item_id === reservation.id);
        await session.api.putOverride(tripId, "reservation", reservation.id, existing?.hidden ?? false, cleanReservationOverride(patch));
      } else {
        await session.api.updateReservation(tripId, reservation.id, patch);
      }
      await afterMutation();
      void loadFlights();
    },
    [afterMutation, bundle?.personal.overrides, ensureWritable, guestMutate, isGuest, loadFlights, session.api, tripId],
  );

  const deleteReservation = useCallback(
    async (reservation: Reservation, mode: "shared" | "personal" = "shared") => {
      ensureWritable();
      if (isGuest) {
        guestMutate((local) => {
          local.reservations = local.reservations.filter((item) => item.id !== reservation.id);
        });
        return;
      }
      if (mode === "personal" || reservation._private) {
        await session.api.deletePrivateReservation(tripId, reservation.id);
      } else {
        await session.api.deleteReservation(tripId, reservation.id);
      }
      await afterMutation();
      void loadFlights();
    },
    [afterMutation, ensureWritable, guestMutate, isGuest, loadFlights, session.api, tripId],
  );

  const hidePersonal = useCallback(
    async (itemType: "place" | "reservation", itemId: string, hidden: boolean) => {
      ensureWritable();
      if (isGuest) throw new Error("Personal notes need an account.");
      const existing = bundle?.personal.overrides.find((item) => item.item_type === itemType && item.item_id === itemId);
      await session.api.putOverride(tripId, itemType, itemId, hidden, existing?.data ?? {});
      await afterMutation();
    },
    [afterMutation, bundle?.personal.overrides, ensureWritable, isGuest, session.api, tripId],
  );

  const savePersonalVersion = useCallback(
    async (itemType: "place" | "reservation", itemId: string, data: Record<string, unknown>) => {
      ensureWritable();
      if (isGuest) throw new Error("Personal notes need an account.");
      const existing = bundle?.personal.overrides.find((item) => item.item_type === itemType && item.item_id === itemId);
      await session.api.putOverride(tripId, itemType, itemId, existing?.hidden ?? false, data);
      await afterMutation();
    },
    [afterMutation, bundle?.personal.overrides, ensureWritable, isGuest, session.api, tripId],
  );

  const restorePersonal = useCallback(
    async (itemType: "place" | "reservation", itemId: string) => {
      ensureWritable();
      if (isGuest) throw new Error("Personal notes need an account.");
      await session.api.deleteOverride(tripId, itemType, itemId);
      await afterMutation();
    },
    [afterMutation, ensureWritable, isGuest, session.api, tripId],
  );

  const addExpense = useCallback(
    async (input: ExpenseInput) => {
      ensureWritable();
      if (isGuest) {
        guestMutate((local) => {
          const expense = makeGuestExpense(local.trip.id, input as Partial<Bundle["expenses"][number]>);
          local.expenses.push(expense);
          if (input.splits) {
            for (const split of input.splits) {
              local.expense_splits.push({
                id: crypto.randomUUID(),
                trip_id: local.trip.id,
                expense_id: expense.id,
                user_id: split.user_id,
                amount: split.amount,
                weight: split.weight ?? null,
              });
            }
          }
        });
        return;
      }
      await session.api.addExpense(tripId, input);
      await afterMutation();
    },
    [afterMutation, ensureWritable, guestMutate, isGuest, session.api, tripId],
  );

  const deleteExpense = useCallback(
    async (id: string) => {
      ensureWritable();
      if (isGuest) {
        guestMutate((local) => {
          local.expenses = local.expenses.filter((item) => item.id !== id);
          local.expense_splits = local.expense_splits.filter((item) => item.expense_id !== id);
        });
        return;
      }
      await session.api.deleteExpense(tripId, id);
      await afterMutation();
    },
    [afterMutation, ensureWritable, guestMutate, isGuest, session.api, tripId],
  );

  const addSettlement = useCallback(
    async (input: { from_user: string; to_user: string; amount: number; currency: string; settled_at?: string; note?: string | null }) => {
      ensureWritable();
      if (isGuest) {
        guestMutate((local) => {
          local.settlements.push(makeGuestSettlement(local.trip.id, input));
        });
        return;
      }
      await session.api.addSettlement(tripId, input);
      await afterMutation();
    },
    [afterMutation, ensureWritable, guestMutate, isGuest, session.api, tripId],
  );

  const addChecklistItem = useCallback(
    async (title: string) => {
      ensureWritable();
      const position = Math.max(0, ...(bundle?.checklist.map((item) => item.position) ?? [0])) + 1;
      if (isGuest) {
        guestMutate((local) => {
          local.checklist.push(makeGuestChecklist(local.trip.id, title, position));
        });
        return;
      }
      await session.api.addChecklistItem(tripId, title, position);
      await afterMutation();
    },
    [afterMutation, bundle?.checklist, ensureWritable, guestMutate, isGuest, session.api, tripId],
  );

  const setChecklistChecked = useCallback(
    async (item: ChecklistItem, checked: boolean) => {
      ensureWritable();
      if (isGuest) {
        guestMutate((local) => {
          const target = local.checklist.find((entry) => entry.id === item.id);
          if (target) target.is_checked = checked;
        });
        return;
      }
      await session.api.updateChecklistItem(tripId, item.id, { is_checked: checked });
      await afterMutation();
    },
    [afterMutation, ensureWritable, guestMutate, isGuest, session.api, tripId],
  );

  const deleteChecklistItem = useCallback(
    async (id: string) => {
      ensureWritable();
      if (isGuest) {
        guestMutate((local) => {
          local.checklist = local.checklist.filter((item) => item.id !== id);
        });
        return;
      }
      await session.api.deleteChecklistItem(tripId, id);
      await afterMutation();
    },
    [afterMutation, ensureWritable, guestMutate, isGuest, session.api, tripId],
  );

  return {
    tripId,
    isGuest,
    bundle,
    loading,
    error,
    offline,
    savedOfflineAt,
    canWrite,
    role,
    profile,
    currentUserId,
    currentMember,
    flights,
    flightsError,
    flightsLoading,
    places: merged.places,
    reservations: merged.reservations,
    hiddenPlaces: merged.hiddenPlaces,
    hiddenReservations: merged.hiddenReservations,
    privatePlaces: bundle?.personal.private_places ?? [],
    privateReservations: bundle?.personal.private_reservations ?? [],
    overriddenPlaces: merged.overriddenPlaces,
    overriddenReservations: merged.overriddenReservations,
    reload: load,
    refreshFlights: loadFlights,
    updateTrip,
    deleteTrip,
    updateDayNotes,
    addPlace,
    updatePlace,
    deletePlace,
    setVisited,
    movePlace,
    movePlaceToDay,
    addReservation,
    updateReservation,
    deleteReservation,
    hidePersonal,
    savePersonalVersion,
    restorePersonal,
    addExpense,
    deleteExpense,
    addSettlement,
    addChecklistItem,
    setChecklistChecked,
    deleteChecklistItem,
  };
}

export function flightsForReservation(flights: FlightsEnvelope | null, reservationId: string) {
  return flights?.flights?.[reservationId] ?? null;
}

export function reservationDateKey(reservation: Reservation, timeZone: string): string | null {
  return dateKeyInZone(reservation.start_at, timeZone);
}
