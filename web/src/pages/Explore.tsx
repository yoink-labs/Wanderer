import { ArrowRight, Compass, Search } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { CoverArt } from "../components/CoverArt";
import { ErrorState, PageLoader } from "../components/States";
import { useSession } from "../auth/session";
import type { Guide } from "../types";

function normalize(value: string): string {
  return value.normalize("NFD").replace(/\p{Diacritic}/gu, "").toLowerCase();
}

export default function Explore() {
  const session = useSession();
  const [guides, setGuides] = useState<Guide[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [query, setQuery] = useState("");

  async function load() {
    setLoading(true);
    setError(null);
    try {
      setGuides(await session.api.guides());
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Couldn't load the guides.");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void load();
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  const filtered = useMemo(() => {
    const words = normalize(query).split(/\s+/).filter(Boolean);
    if (!words.length) return guides;
    return guides.filter((guide) => {
      const haystack = normalize(`${guide.title} ${guide.destination ?? ""} ${guide.summary ?? ""}`);
      return words.every((word) => haystack.includes(word));
    });
  }, [guides, query]);

  return (
    <div className="page-shell explore-page">
      <header className="explore-heading">
        <p className="context-line">Field notes from the road</p>
        <h1>Guides worth keeping.</h1>
        <p>Short, honest routes from people who went. Save the shape of a place before you make it yours.</p>
        <label className="search-field search-field--explore">
          <Search size={17} />
          <input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search Kyoto, Lisbon, waterfalls…" aria-label="Search guides" />
        </label>
      </header>

      {loading ? (
        <PageLoader label="Unfolding the guides" />
      ) : error ? (
        <ErrorState title="Couldn't load the guides" message={error} onRetry={() => void load()} />
      ) : filtered.length === 0 ? (
        <div className="tool-empty">
          <span><Compass size={24} /></span>
          <h2>No guide matches “{query.trim()}”</h2>
          <p>Try a city name, a country, or something you'd like to do.</p>
          <button type="button" className="button button--secondary" onClick={() => setQuery("")}>Clear search</button>
        </div>
      ) : (
        <div className="explore-grid">
          {filtered.map((guide, index) => (
            <Link to={`/guides/${guide.id}`} className={`explore-card ${index === 0 ? "explore-card--wide" : ""}`} key={guide.id}>
              <CoverArt seed={guide.id} destination={guide.destination} imageUrl={guide.cover_url} variant={index === 0 ? "hero" : "guide"} />
              <span className="explore-card__shade" aria-hidden="true" />
              <span className="explore-card__copy">
                <span className="explore-card__destination">{guide.destination}</span>
                <span className="explore-card__title">{guide.title}</span>
                <span className="explore-card__summary">{guide.summary}</span>
                <span className="explore-card__link">Open the field guide <ArrowRight size={14} /></span>
              </span>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}
