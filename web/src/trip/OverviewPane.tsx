import { useEffect, useState } from "react";
import {
  BedDouble,
  CalendarDays,
  MapPin,
  Plane,
  Plus,
  Save,
} from "lucide-react";
import { CoverArt } from "../components/CoverArt";
import { AvatarStack } from "../components/Avatar";
import { fmtDateRange } from "../lib/dates";
import { useToast } from "../components/Toast";
import { BookingsView } from "./BookingsView";
import type { TripStore } from "./useTripStore";
import type { Place, Reservation } from "../types";

export function OverviewPane({
  store,
  onAdd,
  onSelect,
  onAddBooking,
  onEditBooking,
}: {
  store: TripStore;
  onAdd: (listId?: string) => void;
  onSelect: (id: string) => void;
  onAddBooking: () => void;
  onEditBooking: (r: Reservation, p: boolean) => void;
}) {
  const trip = store.bundle!.trip;
  const [listName, setListName] = useState("");
  const [addingList, setAddingList] = useState(false);
  const [notes, setNotes] = useState(trip.notes ?? "");
  const { toast } = useToast();
  useEffect(() => setNotes(trip.notes ?? ""), [trip.notes]);
  const ideas = store.places.filter((p) => !p.day_id);
  const lists = store.bundle!.lists;
  const coverPlace = store.places.find(
    (p) =>
      p.photo_url &&
      p.photo_credit &&
      trip.cover_url?.includes(p.photo_url.split("/").at(-2)!),
  );
  const flights = store.reservations.filter((r) => r.type === "flight").length;
  const stays = store.reservations.filter((r) => r.type === "lodging").length;
  function placeCard(p: Place) {
    return (
      <button key={p.id} className="idea-card" onClick={() => onSelect(p.id)}>
        {p.photo_url ? (
          <img src={p.photo_url} alt="" loading="lazy" />
        ) : (
          <span className="idea-card__icon">
            <MapPin size={24} />
          </span>
        )}
        <span>
          <strong>{p.name}</strong>
          <small>{p.address || p.category}</small>
          {p.notes && <small>{p.notes}</small>}
          {p.photo_credit && (
            <small className="photo-credit">Photo: {p.photo_credit}</small>
          )}
        </span>
      </button>
    );
  }
  return (
    <section className="overview-pane" aria-label="Trip overview">
      <div className="overview-cover">
        <CoverArt
          seed={trip.id}
          destination={trip.destination}
          imageUrl={trip.cover_url}
          showMark={false}
        />
        <span className="overview-cover__tag">YOUR NEXT CHAPTER</span>
        {coverPlace?.photo_source_url && (
          <a
            className="overview-cover__credit"
            href={coverPlace.photo_source_url}
            target="_blank"
            rel="noreferrer"
          >
            {coverPlace.photo_credit}
          </a>
        )}
      </div>
      <header className="overview-intro">
        <p className="context-line">{trip.destination}</p>
        <h1>{trip.title}</h1>
        <p>
          <CalendarDays size={16} />
          {fmtDateRange(trip.start_date, trip.end_date)}
        </p>
        <div className="overview-travelers">
          <AvatarStack
            names={store.bundle!.members.map(
              (m) => m.display_name || m.email || "Traveler",
            )}
          />
          <span>
            {store.bundle!.members.length}{" "}
            {store.bundle!.members.length === 1 ? "traveler" : "travelers"} ·{" "}
            {store.bundle!.days.length} days
          </span>
        </div>
      </header>
      <div className="overview-stats">
        <a href="#overview-reservations">
          <Plane size={19} />
          <strong>{flights}</strong> flights
        </a>
        <a href="#overview-reservations">
          <BedDouble size={19} />
          <strong>{stays}</strong> stays
        </a>
        <a href="#overview-places">
          <MapPin size={19} />
          <strong>
            {store.places.filter((p) => p.category !== "note").length}
          </strong>{" "}
          places
        </a>
      </div>
      <section className="overview-section" id="overview-notes">
        <div className="section-heading">
          <h2>Trip notes</h2>
          <button
            className="text-link"
            disabled={!store.canWrite || notes === (trip.notes ?? "")}
            onClick={() =>
              void store
                .updateTrip({ notes })
                .then(() => toast("Notes saved", "success"))
                .catch((e) => toast(e.message, "error"))
            }
          >
            <Save size={14} /> Save
          </button>
        </div>
        <textarea
          aria-label="Trip notes"
          rows={3}
          value={notes}
          readOnly={!store.canWrite}
          placeholder="A few things to remember along the way…"
          onChange={(e) => setNotes(e.target.value)}
        />
      </section>
      <section className="overview-section" id="overview-reservations">
        <BookingsView
          store={store}
          onAdd={onAddBooking}
          onEdit={onEditBooking}
        />
      </section>
      <section className="overview-section" id="overview-places">
        <div className="section-heading">
          <div>
            <p className="context-line">Room for possibility</p>
            <h2>Places to visit</h2>
          </div>
          <button
            className="button button--secondary"
            onClick={() => onAdd()}
            disabled={!store.canWrite}
          >
            <Plus size={16} /> Add place
          </button>
        </div>
        {lists.map((list) => (
          <div className="overview-list" key={list.id}>
            <div className="section-heading">
              <h3>{list.title}</h3>
              <button
                className="text-link"
                disabled={!store.canWrite}
                onClick={() => onAdd(list.id)}
              >
                <Plus size={14} /> Add place
              </button>
            </div>
            {ideas.filter((p) => p.list_id === list.id).map(placeCard)}
            {!ideas.some((p) => p.list_id === list.id) && (
              <p className="quiet-note">Nothing saved here yet.</p>
            )}
          </div>
        ))}
        {ideas.filter((p) => !p.list_id).map(placeCard)}
        {store.canWrite && (
          <form
            className="new-list-form"
            onSubmit={(event) => {
              event.preventDefault();
              setAddingList(true);
              void store
                .addList(listName)
                .then(() => {
                  setListName("");
                  toast("List created", "success");
                })
                .catch((e) => toast(e.message, "error"))
                .finally(() => setAddingList(false));
            }}
          >
            <input
              aria-label="New list name"
              placeholder="A new list, like food or rainy days"
              value={listName}
              onChange={(e) => setListName(e.target.value)}
            />
            <button
              className="button button--secondary"
              disabled={addingList || !listName.trim()}
            >
              <Plus size={15} /> List
            </button>
          </form>
        )}
        {!ideas.length && !lists.length && (
          <p className="quiet-note">Save a place now. Find its day later.</p>
        )}
      </section>
    </section>
  );
}
