import type {
  Bundle,
  ChecklistItem,
  Expense,
  ExpenseInput,
  FlightsEnvelope,
  Guide,
  GuidePlace,
  Invite,
  Member,
  NewTripInput,
  PersonalLayer,
  PersonalOverride,
  Place,
  PlaceInput,
  Profile,
  Reservation,
  ReservationInput,
  Settlement,
  Trip,
} from "../types";

export const USE_TEST_AUTH = import.meta.env.VITE_USE_TEST_AUTH === "1";
export const TEST_TOKEN = (import.meta.env.VITE_WANDERER_TEST_TOKEN as string | undefined) ?? "";
export const API_URL = (
  (import.meta.env.VITE_API_URL as string | undefined) ||
  (USE_TEST_AUTH ? "http://127.0.0.1:8787" : "https://api.yoinklabs.dev")
).replace(/\/$/, "");

export class ApiRequestError extends Error {
  status: number;
  code: string;
  constructor(message: string, status = 0, code = "network_error") {
    super(message);
    this.name = "ApiRequestError";
    this.status = status;
    this.code = code;
  }
}

type TokenGetter = () => Promise<string | null>;

async function parseError(response: Response): Promise<ApiRequestError> {
  let message = `Request failed (${response.status}).`;
  let code = "request_failed";
  try {
    const body = (await response.json()) as { error?: { message?: string; code?: string } };
    if (body?.error?.message) message = body.error.message;
    if (body?.error?.code) code = body.error.code;
  } catch {
    // Not JSON; keep the generic message.
  }
  return new ApiRequestError(message, response.status, code);
}

export class WandererApi {
  private getToken: TokenGetter | null;

  constructor(getToken: TokenGetter | null = null) {
    this.getToken = getToken;
  }

  setTokenGetter(getToken: TokenGetter | null): void {
    this.getToken = getToken;
  }

  private async request<T>(path: string, init: RequestInit = {}, withAuth = true): Promise<T> {
    const headers = new Headers(init.headers);
    if (init.body !== undefined && !(init.body instanceof FormData) && !headers.has("Content-Type")) {
      headers.set("Content-Type", "application/json");
    }
    if (withAuth) {
      const token = this.getToken ? await this.getToken() : USE_TEST_AUTH ? TEST_TOKEN : null;
      if (token) headers.set("Authorization", `Bearer ${token}`);
    }
    let response: Response;
    try {
      response = await fetch(`${API_URL}${path}`, { ...init, headers });
    } catch {
      throw new ApiRequestError("You appear to be offline.", 0, "offline");
    }
    if (!response.ok) throw await parseError(response);
    if (response.status === 204) return undefined as T;
    const text = await response.text();
    if (!text) return undefined as T;
    return JSON.parse(text) as T;
  }

  // Identity
  me(): Promise<Profile> {
    return this.request("/v1/me");
  }

  updateMe(patch: Partial<Profile>): Promise<Profile> {
    return this.request("/v1/me", { method: "PATCH", body: JSON.stringify(patch) });
  }

  deleteMe(): Promise<{ deleted: boolean }> {
    return this.request("/v1/me", { method: "DELETE", body: JSON.stringify({ confirm: "delete" }) });
  }

  claimInvites(): Promise<{ claimed: string[] }> {
    return this.request("/v1/invites/claim", { method: "POST" });
  }

  // Trips
  trips(): Promise<Trip[]> {
    return this.request("/v1/trips");
  }

  createTrip(input: NewTripInput): Promise<Trip> {
    return this.request("/v1/trips", { method: "POST", body: JSON.stringify(input) });
  }

  getTrip(id: string): Promise<Trip> {
    return this.request(`/v1/trips/${encodeURIComponent(id)}`);
  }

  updateTrip(id: string, patch: Partial<Trip>): Promise<Trip> {
    return this.request(`/v1/trips/${encodeURIComponent(id)}`, {
      method: "PATCH",
      body: JSON.stringify(patch),
    });
  }

  deleteTrip(id: string): Promise<{ deleted: boolean }> {
    return this.request(`/v1/trips/${encodeURIComponent(id)}`, { method: "DELETE" });
  }

  bundle(id: string): Promise<Bundle> {
    return this.request(`/v1/trips/${encodeURIComponent(id)}/bundle`);
  }

  shareLink(id: string): Promise<{ share_token: string }> {
    return this.request(`/v1/trips/${encodeURIComponent(id)}/share-link`, { method: "POST" });
  }

  // Days
  addDay(tripId: string, body: { day_index: number; date: string; title?: string | null; notes?: string | null }): Promise<Bundle["days"][number]> {
    return this.request(`/v1/trips/${encodeURIComponent(tripId)}/days`, { method: "POST", body: JSON.stringify(body) });
  }

  updateDay(tripId: string, dayId: string, patch: Partial<Bundle["days"][number]>): Promise<Bundle["days"][number]> {
    return this.request(`/v1/trips/${encodeURIComponent(tripId)}/days/${encodeURIComponent(dayId)}`, {
      method: "PATCH",
      body: JSON.stringify(patch),
    });
  }

  deleteDay(tripId: string, dayId: string): Promise<{ deleted: boolean }> {
    return this.request(`/v1/trips/${encodeURIComponent(tripId)}/days/${encodeURIComponent(dayId)}`, { method: "DELETE" });
  }

  // Places
  addPlace(tripId: string, body: PlaceInput): Promise<Place> {
    return this.request(`/v1/trips/${encodeURIComponent(tripId)}/places`, { method: "POST", body: JSON.stringify(body) });
  }

  updatePlace(tripId: string, id: string, patch: Partial<PlaceInput & Place>): Promise<Place> {
    return this.request(`/v1/trips/${encodeURIComponent(tripId)}/places/${encodeURIComponent(id)}`, {
      method: "PATCH",
      body: JSON.stringify(patch),
    });
  }

  deletePlace(tripId: string, id: string): Promise<{ deleted: boolean }> {
    return this.request(`/v1/trips/${encodeURIComponent(tripId)}/places/${encodeURIComponent(id)}`, { method: "DELETE" });
  }

  // Reservations
  addReservation(tripId: string, body: ReservationInput): Promise<Reservation> {
    return this.request(`/v1/trips/${encodeURIComponent(tripId)}/reservations`, { method: "POST", body: JSON.stringify(body) });
  }

  updateReservation(tripId: string, id: string, patch: Partial<ReservationInput>): Promise<Reservation> {
    return this.request(`/v1/trips/${encodeURIComponent(tripId)}/reservations/${encodeURIComponent(id)}`, {
      method: "PATCH",
      body: JSON.stringify(patch),
    });
  }

  deleteReservation(tripId: string, id: string): Promise<{ deleted: boolean }> {
    return this.request(`/v1/trips/${encodeURIComponent(tripId)}/reservations/${encodeURIComponent(id)}`, { method: "DELETE" });
  }

  // Money
  addExpense(tripId: string, body: ExpenseInput): Promise<Expense> {
    return this.request(`/v1/trips/${encodeURIComponent(tripId)}/expenses`, { method: "POST", body: JSON.stringify(body) });
  }

  updateExpense(tripId: string, id: string, patch: Partial<ExpenseInput>): Promise<Expense> {
    return this.request(`/v1/trips/${encodeURIComponent(tripId)}/expenses/${encodeURIComponent(id)}`, {
      method: "PATCH",
      body: JSON.stringify(patch),
    });
  }

  deleteExpense(tripId: string, id: string): Promise<{ deleted: boolean }> {
    return this.request(`/v1/trips/${encodeURIComponent(tripId)}/expenses/${encodeURIComponent(id)}`, { method: "DELETE" });
  }

  addSettlement(tripId: string, body: { from_user: string; to_user: string; amount: number; currency: string; settled_at?: string; note?: string | null }): Promise<Settlement> {
    return this.request(`/v1/trips/${encodeURIComponent(tripId)}/settlements`, { method: "POST", body: JSON.stringify(body) });
  }

  // Checklist
  addChecklistItem(tripId: string, title: string, position: number): Promise<ChecklistItem> {
    return this.request(`/v1/trips/${encodeURIComponent(tripId)}/checklist`, {
      method: "POST",
      body: JSON.stringify({ title, is_checked: false, position }),
    });
  }

  updateChecklistItem(tripId: string, id: string, patch: Partial<ChecklistItem>): Promise<ChecklistItem> {
    return this.request(`/v1/trips/${encodeURIComponent(tripId)}/checklist/${encodeURIComponent(id)}`, {
      method: "PATCH",
      body: JSON.stringify(patch),
    });
  }

  deleteChecklistItem(tripId: string, id: string): Promise<{ deleted: boolean }> {
    return this.request(`/v1/trips/${encodeURIComponent(tripId)}/checklist/${encodeURIComponent(id)}`, { method: "DELETE" });
  }

  // Personal layer
  personal(tripId: string): Promise<PersonalLayer> {
    return this.request(`/v1/trips/${encodeURIComponent(tripId)}/personal`);
  }

  putOverride(tripId: string, itemType: "place" | "reservation", itemId: string, hidden: boolean, data: Record<string, unknown>): Promise<PersonalOverride> {
    return this.request(`/v1/trips/${encodeURIComponent(tripId)}/personal/overrides/${itemType}/${encodeURIComponent(itemId)}`, {
      method: "PUT",
      body: JSON.stringify({ hidden, data }),
    });
  }

  deleteOverride(tripId: string, itemType: "place" | "reservation", itemId: string): Promise<{ deleted: boolean }> {
    return this.request(`/v1/trips/${encodeURIComponent(tripId)}/personal/overrides/${itemType}/${encodeURIComponent(itemId)}`, {
      method: "DELETE",
    });
  }

  addPrivatePlace(tripId: string, body: PlaceInput): Promise<Place> {
    return this.request(`/v1/trips/${encodeURIComponent(tripId)}/personal/places`, { method: "POST", body: JSON.stringify(body) });
  }

  updatePrivatePlace(tripId: string, id: string, patch: Partial<PlaceInput>): Promise<Place> {
    return this.request(`/v1/trips/${encodeURIComponent(tripId)}/personal/places/${encodeURIComponent(id)}`, {
      method: "PATCH",
      body: JSON.stringify(patch),
    });
  }

  deletePrivatePlace(tripId: string, id: string): Promise<{ deleted: boolean }> {
    return this.request(`/v1/trips/${encodeURIComponent(tripId)}/personal/places/${encodeURIComponent(id)}`, { method: "DELETE" });
  }

  addPrivateReservation(tripId: string, body: ReservationInput): Promise<Reservation> {
    return this.request(`/v1/trips/${encodeURIComponent(tripId)}/personal/reservations`, { method: "POST", body: JSON.stringify(body) });
  }

  updatePrivateReservation(tripId: string, id: string, patch: Partial<ReservationInput>): Promise<Reservation> {
    return this.request(`/v1/trips/${encodeURIComponent(tripId)}/personal/reservations/${encodeURIComponent(id)}`, {
      method: "PATCH",
      body: JSON.stringify(patch),
    });
  }

  deletePrivateReservation(tripId: string, id: string): Promise<{ deleted: boolean }> {
    return this.request(`/v1/trips/${encodeURIComponent(tripId)}/personal/reservations/${encodeURIComponent(id)}`, { method: "DELETE" });
  }

  // Flights
  flights(tripId: string): Promise<FlightsEnvelope> {
    return this.request(`/v1/trips/${encodeURIComponent(tripId)}/flights`);
  }

  // People
  members(tripId: string): Promise<Member[]> {
    return this.request(`/v1/trips/${encodeURIComponent(tripId)}/members`);
  }

  invites(tripId: string): Promise<Invite[]> {
    return this.request(`/v1/trips/${encodeURIComponent(tripId)}/invites`);
  }

  invite(tripId: string, email: string, role: "editor" | "viewer"): Promise<Invite> {
    return this.request(`/v1/trips/${encodeURIComponent(tripId)}/invites`, {
      method: "POST",
      body: JSON.stringify({ email, role }),
    });
  }

  deleteInvite(tripId: string, id: string): Promise<{ deleted: boolean }> {
    return this.request(`/v1/trips/${encodeURIComponent(tripId)}/invites/${encodeURIComponent(id)}`, { method: "DELETE" });
  }

  // Public guides
  guides(query = ""): Promise<Guide[]> {
    const q = query.trim() ? `?q=${encodeURIComponent(query.trim())}` : "";
    return this.request(`/v1/guides${q}`, {}, false);
  }

  guide(id: string): Promise<Guide> {
    return this.request(`/v1/guides/${encodeURIComponent(id)}`, {}, false);
  }

  guidePlaces(id: string): Promise<GuidePlace[]> {
    return this.request(`/v1/guides/${encodeURIComponent(id)}/places`, {}, false);
  }
}

export function shareUrl(token: string | null): string | null {
  if (!token) return null;
  return `${API_URL}/s/${encodeURIComponent(token)}`;
}
