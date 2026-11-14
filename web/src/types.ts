export type PlaceCategory = "sight" | "food" | "lodging" | "activity" | "transport" | "shopping" | "note";
export type ReservationType = "flight" | "lodging" | "car" | "restaurant" | "train" | "other";
export type ExpenseCategory = "food" | "lodging" | "transport" | "activities" | "shopping" | "other";
export type SplitMode = "equal" | "exact" | "percent" | "shares";
export type TripRole = "owner" | "editor" | "viewer";

export interface Profile {
  id: string;
  email: string | null;
  display_name: string | null;
  avatar_url: string | null;
  locale: string;
  currency: string;
  units: string;
}

export interface Trip {
  id: string;
  owner_id: string;
  title: string;
  destination: string | null;
  start_date: string | null;
  end_date: string | null;
  currency: string;
  cover_url: string | null;
  cover_color: string | null;
  notes: string | null;
  timezone: string;
  share_token: string | null;
  created_at?: string;
  updated_at?: string;
  place_count?: number;
}

export interface TripDay {
  id: string;
  trip_id: string;
  day_index: number;
  date: string | null;
  title: string | null;
  notes: string | null;
}

export interface Place {
  id: string;
  trip_id: string;
  day_id: string | null;
  list_id: string | null;
  name: string;
  address: string | null;
  lat: number | null;
  lng: number | null;
  category: PlaceCategory;
  notes: string | null;
  website: string | null;
  phone: string | null;
  price_level: number | null;
  rating: number | null;
  photo_url: string | null;
  start_time: string | null;
  end_time: string | null;
  position: number;
  visited_at: string | null;
  created_by?: string | null;
  created_at?: string;
  /** Client-only: this stop comes from the personal layer. */
  _private?: boolean;
  /** Client-only: this shared stop has a personal override. */
  _overridden?: boolean;
}

export interface TripList {
  id: string;
  trip_id: string;
  title: string;
  position: number;
}

export interface Reservation {
  id: string;
  trip_id: string;
  type: ReservationType;
  title: string;
  provider: string | null;
  confirmation_code: string | null;
  start_at: string | null;
  end_at: string | null;
  start_location: string | null;
  end_location: string | null;
  cost: number | null;
  currency: string | null;
  notes: string | null;
  metadata: Record<string, unknown>;
  created_by?: string | null;
  created_at?: string;
  _private?: boolean;
  _overridden?: boolean;
}

export interface Expense {
  id: string;
  trip_id: string;
  title: string;
  amount: number;
  currency: string;
  category: ExpenseCategory;
  paid_by: string | null;
  split_with: string[];
  split_mode: SplitMode;
  spent_at: string;
  notes: string | null;
  place_id: string | null;
  created_by?: string | null;
  created_at?: string;
}

export interface ExpenseSplit {
  id: string;
  trip_id: string;
  expense_id: string;
  user_id: string;
  amount: number;
  weight: number | null;
}

export interface Settlement {
  id: string;
  trip_id: string;
  from_user: string;
  to_user: string;
  amount: number;
  currency: string;
  settled_at: string;
  note: string | null;
  created_by?: string | null;
  created_at?: string;
}

export interface ChecklistItem {
  id: string;
  trip_id: string;
  title: string;
  is_checked: boolean;
  position: number;
  created_by?: string | null;
  created_at?: string;
}

export interface Member {
  trip_id?: string;
  user_id: string;
  role: TripRole;
  profile_id?: string;
  display_name: string | null;
  email: string | null;
  joined_at?: string;
  profiles?: { id: string; display_name: string | null; email: string | null };
}

export interface PersonalOverride {
  item_type: "place" | "reservation";
  item_id: string;
  hidden: boolean;
  data: Record<string, unknown>;
  updated_at?: string;
}

export interface PersonalLayer {
  overrides: PersonalOverride[];
  private_places: Place[];
  private_reservations: Reservation[];
}

export interface Bundle {
  trip: Trip;
  days: TripDay[];
  places: Place[];
  lists: TripList[];
  reservations: Reservation[];
  expenses: Expense[];
  expense_splits: ExpenseSplit[];
  settlements: Settlement[];
  checklist: ChecklistItem[];
  members: Member[];
  personal: PersonalLayer;
}

export interface Invite {
  id: string;
  trip_id: string;
  email: string;
  role: TripRole;
  token?: string;
  expires_at: string | null;
  accepted_at: string | null;
  created_at?: string;
  email_delivered?: boolean;
}

export interface FlightEnd {
  airport: string | null;
  airport_name: string | null;
  city: string | null;
  terminal: string | null;
  gate: string | null;
  scheduled: string | null;
  estimated: string | null;
  actual: string | null;
  delay_minutes: number | null;
}

export interface FlightStatus {
  flight_number: string;
  date: string;
  status: string;
  status_label: string;
  airline: { name: string | null; iata: string | null } | null;
  aircraft: string | null;
  departure: FlightEnd;
  arrival: FlightEnd;
  great_circle_km: number | null;
  updated_at: string;
  source: string;
  attribution: string;
}

export interface FlightLookup {
  flight: FlightStatus | null;
  cached: boolean;
  stale: boolean;
  fetched_at?: string | null;
  attribution: string;
  budget_exhausted: boolean;
}

export interface FlightBudget {
  units_used: number;
  requests_used: number;
  units_cap: number;
  requests_cap: number;
}

export interface FlightsEnvelope {
  flights: Record<string, FlightLookup>;
  refreshed?: number;
  attribution: string;
  budget: FlightBudget;
}

export interface Guide {
  id: string;
  title: string;
  summary: string | null;
  destination: string | null;
  cover_url: string | null;
  is_published?: boolean;
}

export interface GuidePlace {
  id: string;
  guide_id: string;
  name: string;
  address: string | null;
  lat: number | null;
  lng: number | null;
  notes: string | null;
  photo_url: string | null;
  position: number;
}

export interface NewTripInput {
  title: string;
  destination: string;
  start_date: string;
  end_date: string;
  currency: string;
  timezone: string;
}

export interface PlaceInput {
  day_id?: string | null;
  list_id?: string | null;
  name: string;
  address?: string | null;
  lat?: number | null;
  lng?: number | null;
  category?: PlaceCategory;
  notes?: string | null;
  website?: string | null;
  phone?: string | null;
  price_level?: number | null;
  rating?: number | null;
  photo_url?: string | null;
  start_time?: string | null;
  end_time?: string | null;
  position?: number;
  visited_at?: string | null;
}

export interface ReservationInput {
  type: ReservationType;
  title: string;
  provider?: string | null;
  confirmation_code?: string | null;
  start_at?: string | null;
  end_at?: string | null;
  start_location?: string | null;
  end_location?: string | null;
  cost?: number | null;
  currency?: string | null;
  notes?: string | null;
  metadata?: Record<string, unknown>;
}

export interface ExpenseInput {
  title: string;
  amount: number;
  currency: string;
  category: ExpenseCategory;
  paid_by: string | null;
  split_with: string[];
  split_mode: SplitMode;
  spent_at: string;
  notes?: string | null;
  place_id?: string | null;
  splits?: Array<{ user_id: string; amount: number; weight?: number | null }>;
}

export interface ApiErrorShape {
  error?: { code?: string; message?: string };
}
