import { ArrowLeft, ArrowRight, MapPin, Route } from "lucide-react";
import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { useSession } from "../auth/session";
import { CoverArt } from "../components/CoverArt";
import { ErrorState, PageLoader } from "../components/CompactStates";
import type { Guide, GuidePlace } from "../types";

export default function GuideDetail() {
  const { guideId } = useParams();
  const session = useSession();
  const [guide, setGuide] = useState<Guide | null>(null);
  const [places, setPlaces] = useState<GuidePlace[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  async function load() {
    if (!guideId) return;
    setLoading(true);
    setError(null);
    try {
      const [loadedGuide, loadedPlaces] = await Promise.all([
        session.api.guide(guideId),
        session.api.guidePlaces(guideId),
      ]);
      setGuide(loadedGuide);
      setPlaces(loadedPlaces);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Couldn't open this guide.");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void load();
  }, [guideId]); // eslint-disable-line react-hooks/exhaustive-deps

  if (loading) return <div className="page-shell"><PageLoader label="Opening the guide" /></div>;
  if (error || !guide) {
    return (
      <div className="page-shell page-shell--narrow">
        <ErrorState title="Couldn't open this guide" message={error ?? undefined} onRetry={() => void load()} />
      </div>
    );
  }

  const mapUrl = places.length >= 2 && places.every((place) => place.lat != null && place.lng != null)
    ? `https://www.google.com/maps/dir/?api=1&origin=${places[0].lat},${places[0].lng}&destination=${places[places.length - 1].lat},${places[places.length - 1].lng}${places.length > 2 ? `&waypoints=${places.slice(1, -1).map((place) => `${place.lat},${place.lng}`).join("|")}` : ""}`
    : null;

  return (
    <div className="guide-detail">
      <section className="guide-hero">
        <CoverArt seed={guide.id} destination={guide.destination} imageUrl={guide.cover_url} variant="hero" />
        <div className="guide-hero__shade" aria-hidden="true" />
        <div className="guide-hero__content">
          <Link to="/guides" className="guide-hero__back"><ArrowLeft size={15} /> All guides</Link>
          <p className="context-line">{guide.destination}</p>
          <h1>{guide.title}</h1>
          <p>{guide.summary}</p>
        </div>
      </section>

      <div className="page-shell guide-body">
        <div className="guide-intro">
          <div>
            <p className="context-line">The route</p>
            <h2>{places.length} places, in order.</h2>
          </div>
          {mapUrl && (
            <a href={mapUrl} target="_blank" rel="noreferrer" className="button button--secondary">
              <Route size={16} /> Open the route in Google Maps
            </a>
          )}
        </div>

        {places.length === 0 ? (
          <p className="quiet-note">This guide doesn't have any places listed yet.</p>
        ) : (
          <ol className="guide-places">
            {places.map((place, index) => (
              <li className="guide-place" key={place.id}>
                <span className="guide-place__index">{String(index + 1).padStart(2, "0")}</span>
                <div className="guide-place__copy">
                  <div className="guide-place__top">
                    <h3>{place.name}</h3>
                    {place.lat != null && place.lng != null && (
                      <a
                        className="guide-place__map-link"
                        href={`https://www.openstreetmap.org/?mlat=${place.lat}&mlon=${place.lng}#map=16/${place.lat}/${place.lng}`}
                        target="_blank"
                        rel="noreferrer"
                        title="Open in OpenStreetMap"
                        aria-label={`Open ${place.name} in OpenStreetMap`}
                      >
                        <MapPin size={15} />
                      </a>
                    )}
                  </div>
                  {place.address && <p className="guide-place__address">{place.address}</p>}
                  {place.notes && <p className="guide-place__notes">{place.notes}</p>}
                </div>
              </li>
            ))}
          </ol>
        )}

        <div className="guide-footer">
          <p>Built by travellers, not an algorithm. Save these places into your own trip from the plan when you're ready.</p>
          <Link to="/guides" className="text-link">More field guides <ArrowRight size={14} /></Link>
        </div>
      </div>
    </div>
  );
}
