import { useEffect, useState } from "react";
import { Check, ExternalLink, MapPin, Pencil, Phone, X } from "lucide-react";
import type { Place } from "../types";
import type { TripStore } from "./useTripStore";
import { useToast } from "../components/Toast";
export function PlaceDetail({
  place,
  store,
  onClose,
  onEdit,
}: {
  place: Place;
  store: TripStore;
  onClose: () => void;
  onEdit: (p: Place, personal: boolean) => void;
}) {
  const [tab, setTab] = useState<"about" | "photos">("about");
  const [notes, setNotes] = useState(place.notes ?? "");
  const { toast } = useToast();
  useEffect(() => {
    setNotes(place.notes ?? "");
    setTab("about");
  }, [place.id, place.notes]);
  const safeLink = (value: string) =>
    /^https?:\/\//i.test(value) ? value : null;
  return (
    <aside className="place-detail" aria-label={`Details for ${place.name}`}>
      <header>
        <span className="context-line">Place details</span>
        <button
          className="icon-button"
          aria-label="Close place details"
          onClick={onClose}
        >
          <X size={20} />
        </button>
      </header>
      {place.photo_url && (
        <img
          className="place-detail__photo"
          src={place.photo_url}
          alt={place.name}
        />
      )}
      {place.photo_credit && place.photo_source_url && (
        <a
          className="photo-credit"
          href={place.photo_source_url}
          target="_blank"
          rel="noreferrer"
        >
          Photo: {place.photo_credit}
        </a>
      )}
      <div className="place-detail__body">
        <p className="context-line">{place.category}</p>
        <h2>{place.name}</h2>
        <nav className="detail-tabs">
          <button
            className={tab === "about" ? "is-active" : ""}
            onClick={() => setTab("about")}
          >
            About
          </button>
          <button
            className={tab === "photos" ? "is-active" : ""}
            onClick={() => setTab("photos")}
          >
            Photos
          </button>
        </nav>
        {tab === "photos" ? (
          place.photo_url ? (
            <img
              className="place-detail__photo"
              src={place.photo_url}
              alt={place.name}
            />
          ) : (
            <p className="quiet-note">
              No photos have been added for this place.
            </p>
          )
        ) : (
          <>
            <p>
              {place.description ||
                "A place in your trip. Add the details that matter to you."}
            </p>
            {place.address && (
              <p className="detail-address">
                <MapPin size={17} />
                {place.address}
              </p>
            )}
            {place.opening_hours && (
              <p>
                <strong>Hours from OpenStreetMap</strong>
                <br />
                {place.opening_hours}
              </p>
            )}
            {place.phone && (
              <p>
                <Phone size={15} /> {place.phone}
              </p>
            )}
            {place.website && safeLink(place.website) && (
              <a
                className="text-link"
                href={place.website}
                target="_blank"
                rel="noreferrer"
              >
                Visit website <ExternalLink size={14} />
              </a>
            )}
            <a
              className="text-link"
              target="_blank"
              rel="noreferrer"
              href={`https://www.openstreetmap.org/${place.lat != null && place.lng != null ? `?mlat=${place.lat}&mlon=${place.lng}#map=16/${place.lat}/${place.lng}` : `search?query=${encodeURIComponent(place.name)}`}`}
            >
              Open map <ExternalLink size={14} />
            </a>
            <label className="field">
              <span className="field__label">Your trip notes</span>
              <textarea
                rows={7}
                value={notes}
                readOnly={!store.canWrite}
                onChange={(e) => setNotes(e.target.value)}
              />
            </label>
            <button
              className="button button--secondary"
              disabled={!store.canWrite || notes === (place.notes ?? "")}
              onClick={() =>
                void store
                  .updatePlace(
                    place,
                    { notes },
                    place._private ? "personal" : "shared",
                  )
                  .then(() => toast("Place notes saved", "success"))
                  .catch((e) => toast(e.message, "error"))
              }
            >
              Save notes
            </button>
            <div className="detail-actions">
              <button
                className="button button--primary"
                disabled={!store.canWrite}
                onClick={() =>
                  void store
                    .setVisited(place, !place.visited_at)
                    .catch((e) => toast(e.message, "error"))
                }
              >
                <Check size={16} />
                {place.visited_at ? "Visited" : "Mark visited"}
              </button>
              <button
                className="icon-button"
                disabled={!store.canWrite}
                aria-label="Edit place"
                onClick={() => onEdit(place, false)}
              >
                <Pencil size={17} />
              </button>
            </div>
          </>
        )}
      </div>
    </aside>
  );
}
