import { ArrowRight, CalendarDays, Map, Plus, Search, Sparkles, X } from "lucide-react";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { useSession } from "../auth/session";
import { AvatarStack } from "../components/Avatar";
import { CoverArt } from "../components/CoverArt";
import { GuestMark } from "../components/AppHeader";
import { PlanTripDialog } from "../components/PlanTripDialog";
import { HomeSkeleton, ErrorState, EmptyState } from "../components/States";
import { useToast } from "../components/Toast";
import { countdownLabel, dayCount, daysUntil, fmtDateRange, tripPhase } from "../lib/dates";
import { plural, summaryName } from "../lib/format";
import { guestTrips, loadGuestBundles, migrateGuestTrips } from "../lib/guest";
import Landing from "./Landing";
import type { Guide, Member, Trip } from "../types";

interface TripRow extends Trip {
  members: Member[];
}

const RECENT_KEY = "wanderer.recentTrips";

function readRecent(): string[] {
  try {
    const parsed = JSON.parse(localStorage.getItem(RECENT_KEY) || "[]") as unknown;
    return Array.isArray(parsed) ? parsed.filter((item): item is string => typeof item === "string") : [];
  } catch {
    return [];
  }
}

function normalize(value: string): string {
  return value.normalize("NFD").replace(/\p{Diacritic}/gu, "").toLowerCase();
}

function searchTrips(trips: TripRow[], query: string): TripRow[] {
  const words = normalize(query).split(/\s+/).filter(Boolean);
  if (!words.length) return trips;
  return trips.filter((trip) => {
    const haystack = normalize(`${trip.title} ${trip.destination ?? ""} ${trip.start_date ?? ""} ${trip.end_date ?? ""}`);
    return words.every((word) => haystack.includes(word));
  });
}

function searchGuides(guides: Guide[], query: string): Guide[] {
  const words = normalize(query).split(/\s+/).filter(Boolean);
  if (!words.length) return guides;
  return guides.filter((guide) => {
    const haystack = normalize(`${guide.title} ${guide.destination ?? ""} ${guide.summary ?? ""}`);
    return words.every((word) => haystack.includes(word));
  });
}

function orderTrips(trips: TripRow[]): { featured: TripRow | null; others: TripRow[] } {
  if (!trips.length) return { featured: null, others: [] };
  const recent = readRecent();
  const now = new Date();
  const live = trips.find((trip) => tripPhase(trip.start_date, trip.end_date, now) === "inProgress");
  const recentTrip = recent
    .map((id) => trips.find((trip) => trip.id === id))
    .find((trip): trip is TripRow => Boolean(trip && tripPhase(trip.start_date, trip.end_date, now) !== "past"));
  const upcoming = trips
    .filter((trip) => tripPhase(trip.start_date, trip.end_date, now) === "upcoming")
    .sort((a, b) => (a.start_date ?? "9999").localeCompare(b.start_date ?? "9999"))[0];
  const featured = live ?? recentTrip ?? upcoming ?? trips[0];
  const rest = trips.filter((trip) => trip.id !== featured.id);
  const current = rest
    .filter((trip) => tripPhase(trip.start_date, trip.end_date, now) !== "past")
    .sort((a, b) => (a.start_date ?? "9999").localeCompare(b.start_date ?? "9999"));
  const past = rest
    .filter((trip) => tripPhase(trip.start_date, trip.end_date, now) === "past")
    .sort((a, b) => (b.end_date ?? "").localeCompare(a.end_date ?? ""));
  return { featured, others: [...current, ...past] };
}

function featuredLabel(trip: TripRow): string {
  const phase = tripPhase(trip.start_date, trip.end_date);
  if (phase === "inProgress") return "Happening now";
  if (phase === "past") return "From the archive";
  const days = daysUntil(trip.start_date);
  if (days === 0) return "Starts today";
  if (days === 1) return "Starts tomorrow";
  if (days && days > 1) return `Up next · ${days} days`;
  return "Up next";
}

function memberNames(trip: TripRow): string[] {
  return trip.members.map((member) => summaryName(member.display_name, member.email));
}

export default function Home() {
  const session = useSession();
  // Marketing needs no API round trip. Existing guest plans still open the atlas.
  return !session.isSignedIn && guestTrips().length === 0 ? <Landing /> : <TripHome />;
}

function TripHome() {
  const session = useSession();
  const navigate = useNavigate();
  const { toast } = useToast();
  const [trips, setTrips] = useState<TripRow[]>([]);
  const [guides, setGuides] = useState<Guide[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [guidesError, setGuidesError] = useState<string | null>(null);
  const [query, setQuery] = useState("");
  const [planOpen, setPlanOpen] = useState(false);
  const didMigrate = useRef(false);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    setGuidesError(null);
    try {
      const guidesPromise = session.api.guides().catch((caught) => {
        setGuidesError(caught instanceof Error ? caught.message : "Guides are unavailable.");
        return [] as Guide[];
      });
      let rows: TripRow[] = [];
      if (session.isSignedIn) {
        if (!didMigrate.current) {
          didMigrate.current = true;
          const local = loadGuestBundles();
          if (local.length) {
            const result = await migrateGuestTrips(session.api).catch(() => ({ imported: 0, failed: local.length }));
            if (result.imported) toast(`${plural(result.imported, "guest trip")} copied to your account`, "success");
            if (result.failed) toast("Some guest trips couldn’t be copied yet. They’re still on this device.", "error");
          }
          await session.api.claimInvites().catch(() => undefined);
        }
        const remoteTrips = await session.api.trips();
        const memberPairs = await Promise.allSettled(remoteTrips.map((trip) => session.api.members(trip.id)));
        rows = remoteTrips.map((trip, index) => {
          const membersResult = memberPairs[index];
          return {
            ...trip,
            members: membersResult.status === "fulfilled" ? membersResult.value : [],
          };
        });
      } else {
        const bundles = loadGuestBundles();
        rows = guestTrips().map((trip) => {
          const bundle = bundles.find((item) => item.trip.id === trip.id);
          return { ...trip, members: bundle?.members ?? [] };
        });
      }
      const officialGuides = await guidesPromise;
      setTrips(rows);
      setGuides(officialGuides);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Couldn't load your trips.");
    } finally {
      setLoading(false);
    }
  }, [session.api, session.isSignedIn, toast]);

  useEffect(() => {
    void load();
  }, [load]);

  const filteredTrips = useMemo(() => searchTrips(trips, query), [trips, query]);
  const filteredGuides = useMemo(() => searchGuides(guides, query), [guides, query]);
  const ordered = useMemo(() => orderTrips(filteredTrips), [filteredTrips]);
  const isSearching = query.trim().length > 0;
  const firstName = session.user?.displayName?.split(" ")[0];
  const todayLine = new Intl.DateTimeFormat(undefined, { weekday: "long", month: "long", day: "numeric" }).format(new Date());

  function openTrip(trip: TripRow) {
    const recent = readRecent().filter((id) => id !== trip.id);
    recent.unshift(trip.id);
    localStorage.setItem(RECENT_KEY, JSON.stringify(recent.slice(0, 8)));
    navigate(`/trips/${trip.id}`);
  }

  return (
    <div className="page-shell home-page">
      <header className="home-heading">
        <div>
          <p className="context-line">{todayLine}</p>
          <h1>{session.isSignedIn ? `${greeting()}, ${firstName}.` : "Your next chapter."}</h1>
          <p className="home-heading__sub">
            {session.isSignedIn
              ? "A quiet place for the trips you're taking and the ones you're still dreaming up."
              : "Plan a trip in this browser, or sign in to keep your plans with you everywhere."}
          </p>
        </div>
        <button type="button" className="button button--primary button--plan" onClick={() => setPlanOpen(true)}>
          <Plus size={18} /> Plan a trip
        </button>
      </header>

      <div className="home-toolbar">
        <label className="search-field">
          <Search size={17} aria-hidden="true" />
          <input
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Search trips and guides"
            aria-label="Search trips and guides"
          />
          {query && (
            <button type="button" className="icon-button icon-button--quiet search-field__clear" onClick={() => setQuery("")} aria-label="Clear search">
              <X size={15} />
            </button>
          )}
        </label>
        {!session.isSignedIn && <GuestMark />}
      </div>

      {loading ? (
        <HomeSkeleton />
      ) : error ? (
        <ErrorState
          title="Couldn't load your trips"
          message={error}
          onRetry={() => void load()}
          retryLabel="Retry"
        />
      ) : isSearching ? (
        <SearchResults
          trips={ordered.featured ? [ordered.featured, ...ordered.others] : []}
          guides={filteredGuides}
          query={query}
          onTrip={openTrip}
          guidesError={guidesError}
        />
      ) : (
        <>
          {trips.length === 0 ? (
            <EmptyHome onPlan={() => setPlanOpen(true)} signedIn={session.isSignedIn} onSignIn={session.signIn} />
          ) : (
            <>
              {ordered.featured && (
                <section className="featured-trip" aria-labelledby="featured-trip-title">
                  <button className="featured-trip__link" type="button" onClick={() => openTrip(ordered.featured!)}>
                    <CoverArt
                      seed={ordered.featured.id}
                      destination={ordered.featured.destination}
                      imageUrl={ordered.featured.cover_url}
                      variant="hero"
                    />
                    <span className="featured-trip__shade" aria-hidden="true" />
                    <span className="featured-trip__content">
                      <span className="pill pill--marigold">{featuredLabel(ordered.featured)}</span>
                      <span className="featured-trip__title" id="featured-trip-title">{ordered.featured.title}</span>
                      <span className="featured-trip__destination">{ordered.featured.destination}</span>
                      <span className="featured-trip__foot">
                        <span className="featured-trip__meta">
                          <CalendarDays size={15} />
                          {fmtDateRange(ordered.featured.start_date, ordered.featured.end_date)}
                          <span className="dot" />
                          {plural(dayCount(ordered.featured.start_date, ordered.featured.end_date), "day")}
                          <span className="dot" />
                          {plural(ordered.featured.place_count ?? 0, "place")}
                        </span>
                        <span className="featured-trip__people">
                          <AvatarStack names={memberNames(ordered.featured)} max={3} />
                          <span className="featured-trip__open">Open trip <ArrowRight size={16} /></span>
                        </span>
                      </span>
                    </span>
                    <RouteSpine trip={ordered.featured} />
                  </button>
                </section>
              )}

              {ordered.others.length > 0 && (
                <section className="home-section" aria-labelledby="other-trips">
                  <div className="section-heading">
                    <div>
                      <p className="context-line">{session.isSignedIn ? "Also in your atlas" : "On this device"}</p>
                      <h2 id="other-trips">The rest of your trips</h2>
                    </div>
                    <span className="count-note">{ordered.others.length} {ordered.others.length === 1 ? "trip" : "trips"}</span>
                  </div>
                  <div className="trip-ledger">
                    {ordered.others.map((trip) => (
                      <button type="button" className="trip-ledger__row" key={trip.id} onClick={() => openTrip(trip)}>
                        <CoverArt seed={trip.id} destination={trip.destination} imageUrl={trip.cover_url} variant="rail" showMark={false} />
                        <span className="trip-ledger__copy">
                          <span className="trip-ledger__title">{trip.title}</span>
                          <span className="trip-ledger__detail">{trip.destination}</span>
                          <span className="trip-ledger__meta">
                            {fmtDateRange(trip.start_date, trip.end_date)}
                            <span className="dot" />
                            {plural(trip.place_count ?? 0, "place")}
                          </span>
                        </span>
                        <span className="trip-ledger__side">
                          <span className={`status-chip ${tripPhase(trip.start_date, trip.end_date) === "past" ? "status-chip--past" : ""}`}>
                            {countdownLabel(trip.start_date, trip.end_date)}
                          </span>
                          <AvatarStack names={memberNames(trip)} max={2} />
                        </span>
                      </button>
                    ))}
                  </div>
                </section>
              )}
            </>
          )}

          <GuidesSection guides={guides} error={guidesError} onRetry={() => void load()} />
        </>
      )}

      <footer className="home-footer">
        <span className="home-footer__word">Wanderer</span>
        <span>Open source. No paywall. Optional tips in the iOS app.</span>
        <button type="button" className="text-link" onClick={() => setPlanOpen(true)}>Start a trip <ArrowRight size={14} /></button>
      </footer>

      <PlanTripDialog open={planOpen} onClose={() => setPlanOpen(false)} />
    </div>
  );
}

function greeting(): string {
  const hour = new Date().getHours();
  if (hour < 12) return "Good morning";
  if (hour < 18) return "Good afternoon";
  return "Good evening";
}

function RouteSpine({ trip }: { trip: Trip }) {
  const count = dayCount(trip.start_date, trip.end_date) || 1;
  const start = trip.start_date;
  let current: number | null = null;
  if (start) {
    const phase = tripPhase(trip.start_date, trip.end_date);
    if (phase === "inProgress") {
      const index = Math.max(0, Math.round((new Date(`${new Date().toISOString().slice(0, 10)}T00:00:00Z`).getTime() - new Date(`${start}T00:00:00Z`).getTime()) / 86400000));
      current = Math.min(index, count - 1);
    }
  }
  const progress = current == null ? (tripPhase(trip.start_date, trip.end_date) === "past" ? 1 : 0) : current / Math.max(1, count - 1);
  return (
    <span className="route-spine" aria-hidden="true">
      <span className="route-spine__track" />
      <span className="route-spine__fill" style={{ width: `${Math.max(0, Math.min(100, progress * 100))}%` }} />
      {count <= 14 && Array.from({ length: count }).map((_, index) => (
        <span
          className={`route-spine__bead ${current === index ? "is-current" : ""} ${current != null && index < current ? "is-done" : ""}`}
          key={index}
          style={{ left: `calc(${count <= 1 ? 0 : (index / (count - 1)) * 100}% - 4px)` }}
        />
      ))}
    </span>
  );
}

function EmptyHome({ onPlan, signedIn, onSignIn }: { onPlan: () => void; signedIn: boolean; onSignIn: () => void }) {
  return (
    <section className="empty-home">
      <div className="empty-home__art" aria-hidden="true">
        <CoverArt seed="a blank map" destination="Somewhere" variant="hero" />
        <span className="empty-home__pin">01</span>
        <span className="empty-home__pin empty-home__pin--two">02</span>
        <span className="empty-home__line" />
      </div>
      <div className="empty-home__copy">
        <p className="context-line">The first page</p>
        <h2>Your atlas is wide open.</h2>
        <p>Start with a destination and a few dates. Add the restaurants, the long walk, the flight that gets you there — Wanderer keeps it all in one calm place.</p>
        <div className="empty-home__actions">
          <button type="button" className="button button--primary button--large" onClick={onPlan}>
            <Plus size={18} /> Plan your first trip
          </button>
          {!signedIn && (
            <button type="button" className="button button--secondary button--large" onClick={onSignIn}>
              Sign in to keep it
            </button>
          )}
        </div>
        <p className="empty-home__foot"><Sparkles size={14} /> No account needed to start planning.</p>
      </div>
    </section>
  );
}

function GuidesSection({ guides, error, onRetry }: { guides: Guide[]; error: string | null; onRetry: () => void }) {
  const shown = guides.slice(0, 3);
  return (
    <section className="home-section guides-section" aria-labelledby="guides-heading">
      <div className="section-heading">
        <div>
          <p className="context-line">Curated by people who went</p>
          <h2 id="guides-heading">Worth the detour</h2>
        </div>
        <Link to="/guides" className="text-link">All guides <ArrowRight size={15} /></Link>
      </div>
      {error ? (
        <div className="inline-error">
          <span>{error}</span>
          <button type="button" className="text-link" onClick={onRetry}>Retry</button>
        </div>
      ) : shown.length === 0 ? (
        <p className="quiet-note">New field guides are on their way.</p>
      ) : (
        <div className="guide-row">
          {shown.map((guide, index) => (
            <Link to={`/guides/${guide.id}`} className={`guide-card guide-card--${index + 1}`} key={guide.id}>
              <CoverArt seed={guide.id} destination={guide.destination} imageUrl={guide.cover_url} variant="guide" />
              <span className="guide-card__copy">
                <span className="guide-card__destination">{guide.destination}</span>
                <span className="guide-card__title">{guide.title}</span>
                <span className="guide-card__summary">{guide.summary}</span>
                <span className="guide-card__link">Read the guide <ArrowRight size={14} /></span>
              </span>
            </Link>
          ))}
        </div>
      )}
    </section>
  );
}

function SearchResults({
  trips,
  guides,
  query,
  onTrip,
  guidesError,
}: {
  trips: TripRow[];
  guides: Guide[];
  query: string;
  onTrip: (trip: TripRow) => void;
  guidesError: string | null;
}) {
  const total = trips.length + guides.length;
  return (
    <section className="search-results" aria-label="Search results">
      <div className="section-heading">
        <div>
          <p className="context-line">Search</p>
          <h2>{total === 0 ? "No matches" : `${total} ${total === 1 ? "result" : "results"}`} for “{query.trim()}”</h2>
        </div>
      </div>
      {total === 0 && (
        <EmptyState
          icon={<Search size={22} />}
          title="Nothing matches yet"
          message="Try a destination, a trip name, or a guide title."
        />
      )}
      {trips.length > 0 && (
        <div className="search-group">
          <h3 className="search-group__heading">Trips</h3>
          {trips.map((trip) => (
            <button type="button" className="search-row" key={trip.id} onClick={() => onTrip(trip)}>
              <CoverArt seed={trip.id} destination={trip.destination} imageUrl={trip.cover_url} variant="rail" showMark={false} />
              <span className="search-row__copy">
                <span className="search-row__title">{trip.title}</span>
                <span className="search-row__meta">{trip.destination} · {fmtDateRange(trip.start_date, trip.end_date)}</span>
              </span>
              <ArrowRight size={16} />
            </button>
          ))}
        </div>
      )}
      {guides.length > 0 && (
        <div className="search-group">
          <h3 className="search-group__heading">Guides</h3>
          {guides.map((guide) => (
            <Link to={`/guides/${guide.id}`} className="search-row" key={guide.id}>
              <CoverArt seed={guide.id} destination={guide.destination} imageUrl={guide.cover_url} variant="rail" showMark={false} />
              <span className="search-row__copy">
                <span className="search-row__title">{guide.title}</span>
                <span className="search-row__meta">{guide.destination} · {guide.summary}</span>
              </span>
              <ArrowRight size={16} />
            </Link>
          ))}
        </div>
      )}
      {guidesError && <p className="quiet-note">Guides couldn't load: {guidesError}</p>}
    </section>
  );
}
