import { EyeOff, RotateCcw, Trash2, UserRound } from "lucide-react";
import { useState } from "react";
import { Dialog } from "../components/Dialog";
import { useToast } from "../components/Toast";
import { ReservationTypeIcon } from "../components/TripBits";
import type { TripStore } from "./useTripStore";

export function OnlyYouPanel({ open, onClose, store }: { open: boolean; onClose: () => void; store: TripStore }) {
  const { toast } = useToast();
  const [busyKey, setBusyKey] = useState<string | null>(null);

  async function restore(type: "place" | "reservation", id: string) {
    setBusyKey(`${type}:${id}`);
    try {
      await store.restorePersonal(type, id);
      toast("Restored to the shared plan", "success");
    } catch (caught) {
      toast(caught instanceof Error ? caught.message : "Couldn't restore that item.", "error");
    } finally {
      setBusyKey(null);
    }
  }

  async function removePrivate(type: "place" | "reservation", id: string) {
    setBusyKey(`${type}:${id}`);
    try {
      if (type === "place") {
        const place = store.privatePlaces.find((item) => item.id === id);
        if (place) await store.deletePlace({ ...place, _private: true }, "personal");
      } else {
        const reservation = store.privateReservations.find((item) => item.id === id);
        if (reservation) await store.deleteReservation({ ...reservation, _private: true }, "personal");
      }
      toast("Private item deleted", "success");
    } catch (caught) {
      toast(caught instanceof Error ? caught.message : "Couldn't delete that item.", "error");
    } finally {
      setBusyKey(null);
    }
  }

  const hiddenCount = store.hiddenPlaces.length + store.hiddenReservations.length;
  const overriddenCount = store.overriddenPlaces.length + store.overriddenReservations.length;
  const privateCount = store.privatePlaces.length + store.privateReservations.length;
  const total = hiddenCount + overriddenCount + privateCount;

  return (
    <Dialog
      open={open}
      onClose={onClose}
      title="Only you"
      description="Your private layer. No one else on this trip can see these changes."
      wide
      footer={<button type="button" className="button button--primary" onClick={onClose}>Done</button>}
    >
      {total === 0 ? (
        <div className="only-you-empty">
          <span><UserRound size={22} /></span>
          <h3>Nothing is just for you yet</h3>
          <p>Use the <strong>Only for me</strong> menu on any stop or booking to hide it, save your own version, or add something private.</p>
        </div>
      ) : (
        <div className="only-you-content">
          <div className="personal-summary">
            <span><EyeOff size={14} /> {hiddenCount} hidden</span>
            <span><UserRound size={14} /> {overriddenCount} edited</span>
            <span><UserRound size={14} /> {privateCount} private</span>
          </div>

          {store.privatePlaces.length > 0 && (
            <section className="personal-group">
              <h3>Private stops</h3>
              <p className="personal-group__hint">These never appear in the group's itinerary.</p>
              {store.privatePlaces.map((place) => (
                <div className="personal-row" key={place.id}>
                  <span className="personal-row__icon"><UserRound size={15} /></span>
                  <span className="personal-row__copy">
                    <strong>{place.name}</strong>
                    <small>{place.address || "Private place"}</small>
                  </span>
                  <span className="personal-row__badge">Only you</span>
                  <button
                    type="button"
                    className="icon-button icon-button--quiet is-danger"
                    onClick={() => void removePrivate("place", place.id)}
                    disabled={busyKey === `place:${place.id}` || !store.canWrite}
                    aria-label={`Delete private stop ${place.name}`}
                    title="Delete this private stop"
                  >
                    <Trash2 size={16} />
                  </button>
                </div>
              ))}
            </section>
          )}

          {store.privateReservations.length > 0 && (
            <section className="personal-group">
              <h3>Private bookings</h3>
              <p className="personal-group__hint">Only you see the confirmation details and times.</p>
              {store.privateReservations.map((reservation) => (
                <div className="personal-row" key={reservation.id}>
                  <span className="personal-row__icon"><ReservationTypeIcon type={reservation.type} size={15} /></span>
                  <span className="personal-row__copy">
                    <strong>{reservation.title}</strong>
                    <small>{reservation.provider || "Private booking"}</small>
                  </span>
                  <span className="personal-row__badge">Only you</span>
                  <button
                    type="button"
                    className="icon-button icon-button--quiet is-danger"
                    onClick={() => void removePrivate("reservation", reservation.id)}
                    disabled={busyKey === `reservation:${reservation.id}` || !store.canWrite}
                    aria-label={`Delete private booking ${reservation.title}`}
                    title="Delete this private booking"
                  >
                    <Trash2 size={16} />
                  </button>
                </div>
              ))}
            </section>
          )}

          {store.hiddenPlaces.length + store.hiddenReservations.length > 0 && (
            <section className="personal-group">
              <h3>Hidden for you</h3>
              <p className="personal-group__hint">The group still sees these. They're just out of your way.</p>
              {store.hiddenPlaces.map((place) => (
                <div className="personal-row" key={place.id}>
                  <span className="personal-row__icon"><EyeOff size={15} /></span>
                  <span className="personal-row__copy">
                    <strong>{place.name}</strong>
                    <small>Shared stop, hidden from your plan</small>
                  </span>
                  <button
                    type="button"
                    className="button button--secondary button--small"
                    onClick={() => void restore("place", place.id)}
                    disabled={busyKey === `place:${place.id}` || !store.canWrite}
                  >
                    <RotateCcw size={14} /> Restore
                  </button>
                </div>
              ))}
              {store.hiddenReservations.map((reservation) => (
                <div className="personal-row" key={reservation.id}>
                  <span className="personal-row__icon"><EyeOff size={15} /></span>
                  <span className="personal-row__copy">
                    <strong>{reservation.title}</strong>
                    <small>Shared booking, hidden from your plan</small>
                  </span>
                  <button
                    type="button"
                    className="button button--secondary button--small"
                    onClick={() => void restore("reservation", reservation.id)}
                    disabled={busyKey === `reservation:${reservation.id}` || !store.canWrite}
                  >
                    <RotateCcw size={14} /> Restore
                  </button>
                </div>
              ))}
            </section>
          )}

          {store.overriddenPlaces.length + store.overriddenReservations.length > 0 && (
            <section className="personal-group">
              <h3>Your versions</h3>
              <p className="personal-group__hint">You replaced the shared details for yourself. The original is still there for everyone else.</p>
              {store.overriddenPlaces.map((place) => (
                <div className="personal-row" key={place.id}>
                  <span className="personal-row__icon"><UserRound size={15} /></span>
                  <span className="personal-row__copy">
                    <strong>{place.name}</strong>
                    <small>Your version of a shared stop</small>
                  </span>
                  <button
                    type="button"
                    className="button button--secondary button--small"
                    onClick={() => void restore("place", place.id)}
                    disabled={busyKey === `place:${place.id}` || !store.canWrite}
                  >
                    <RotateCcw size={14} /> Use original
                  </button>
                </div>
              ))}
              {store.overriddenReservations.map((reservation) => (
                <div className="personal-row" key={reservation.id}>
                  <span className="personal-row__icon"><UserRound size={15} /></span>
                  <span className="personal-row__copy">
                    <strong>{reservation.title}</strong>
                    <small>Your version of a shared booking</small>
                  </span>
                  <button
                    type="button"
                    className="button button--secondary button--small"
                    onClick={() => void restore("reservation", reservation.id)}
                    disabled={busyKey === `reservation:${reservation.id}` || !store.canWrite}
                  >
                    <RotateCcw size={14} /> Use original
                  </button>
                </div>
              ))}
            </section>
          )}
        </div>
      )}
    </Dialog>
  );
}
