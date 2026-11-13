import L from "leaflet";
import { Expand, Layers3, MapPinOff } from "lucide-react";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useTheme } from "../lib/theme";
import type { Place, TripDay } from "../types";

interface MapPaneProps {
  places: Place[];
  days: TripDay[];
  focusDayId: string | null;
  onFocusDay: (dayId: string | null) => void;
  selectedPlaceId: string | null;
  onSelectPlace: (placeId: string) => void;
}

function hasCoordinates(place: Place): place is Place & { lat: number; lng: number } {
  return typeof place.lat === "number" && typeof place.lng === "number" && Number.isFinite(place.lat) && Number.isFinite(place.lng);
}

export function MapPane({ places, days, focusDayId, onFocusDay, selectedPlaceId, onSelectPlace }: MapPaneProps) {
  const theme = useTheme();
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<L.Map | null>(null);
  const layerRef = useRef<L.LayerGroup | null>(null);
  const selectedRef = useRef(selectedPlaceId);
  const [dayFilter, setDayFilter] = useState<string | null>(focusDayId);
  selectedRef.current = selectedPlaceId;

  useEffect(() => {
    setDayFilter(focusDayId);
  }, [focusDayId]);

  const daysWithPlaces = useMemo(() => {
    return days.filter((day) => places.some((place) => place.day_id === day.id));
  }, [days, places]);

  const filtered = useMemo(() => {
    if (dayFilter === null) return places.filter(hasCoordinates);
    if (dayFilter === "unscheduled") return places.filter((place) => !place.day_id && hasCoordinates(place));
    return places.filter((place) => place.day_id === dayFilter && hasCoordinates(place));
  }, [dayFilter, places]);

  const allPinned = useMemo(() => places.filter(hasCoordinates), [places]);

  const fit = useCallback(() => {
    const map = mapRef.current;
    if (!map) return;
    const points = filtered.map((place) => L.latLng(place.lat!, place.lng!));
    if (!points.length) {
      map.setView([24, 8], 2, { animate: true });
      return;
    }
    if (points.length === 1) {
      map.flyTo(points[0], 14, { duration: 0.45 });
      return;
    }
    map.fitBounds(L.latLngBounds(points), { padding: [48, 48], maxZoom: 15, animate: true });
  }, [filtered]);

  useEffect(() => {
    if (!containerRef.current || mapRef.current) return;
    const map = L.map(containerRef.current, {
      zoomControl: false,
      attributionControl: true,
      scrollWheelZoom: true,
    }).setView([24, 8], 2);
    L.control.zoom({ position: "bottomright" }).addTo(map);
    L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 19,
      attribution:
        '&copy; <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noreferrer">OpenStreetMap</a> contributors',
    }).addTo(map);
    mapRef.current = map;
    layerRef.current = L.layerGroup().addTo(map);

    const resize = new ResizeObserver(() => map.invalidateSize());
    resize.observe(containerRef.current);
    window.setTimeout(() => map.invalidateSize(), 120);

    return () => {
      resize.disconnect();
      map.remove();
      mapRef.current = null;
      layerRef.current = null;
    };
  }, []);

  useEffect(() => {
    const map = mapRef.current;
    const layer = layerRef.current;
    if (!map || !layer) return;
    layer.clearLayers();

    const groups = new Map<string, Array<Place & { lat: number; lng: number }>>();
    for (const place of filtered) {
      if (!hasCoordinates(place)) continue;
      const key = place.day_id ?? "unscheduled";
      const group = groups.get(key) ?? [];
      group.push(place);
      groups.set(key, group);
    }

    const allPins: Array<{ place: Place & { lat: number; lng: number }; number: number }> = [];
    let running = 1;
    const dayOrder = new Map(days.map((day) => [day.id, day.day_index]));
    const sortedGroups = [...groups.entries()].sort(([a], [b]) => {
      if (a === "unscheduled") return 1;
      if (b === "unscheduled") return -1;
      return (dayOrder.get(a) ?? 0) - (dayOrder.get(b) ?? 0);
    });
    for (const [, group] of sortedGroups) {
      for (const place of group) {
        allPins.push({ place, number: running });
        running += 1;
      }
      if (group.length > 1) {
        L.polyline(
          group.map((place) => [place.lat, place.lng] as [number, number]),
          {
            color: "#F2A922",
            weight: 3,
            opacity: 0.9,
            lineJoin: "round",
            lineCap: "round",
          },
        ).addTo(layer);
      }
    }

    for (const { place, number } of allPins) {
      const selected = place.id === selectedRef.current;
      const icon = L.divIcon({
        className: "wanderer-marker-host",
        html: `<span class="wanderer-marker${selected ? " is-selected" : ""}" data-place-id="${place.id}"><span>${number}</span></span>`,
        iconSize: [34, 34],
        iconAnchor: [17, 17],
      });
      const marker = L.marker([place.lat, place.lng], { icon, keyboard: true, title: place.name, alt: place.name });
      marker.on("click", () => onSelectPlace(place.id));
      marker.addTo(layer);
    }

    fit();
  }, [dayFilter, days, filtered, fit, onSelectPlace]);

  useEffect(() => {
    const layer = layerRef.current;
    if (!layer) return;
    layer.eachLayer((entry) => {
      if (!(entry instanceof L.Marker)) return;
      const el = entry.getElement()?.querySelector<HTMLElement>(".wanderer-marker");
      if (!el) return;
      const id = el.dataset.placeId;
      el.classList.toggle("is-selected", id === selectedPlaceId);
    });
  }, [selectedPlaceId]);

  const dayLabel = dayFilter === null ? "All days" : dayFilter === "unscheduled" ? "Unscheduled" : `Day ${(days.find((day) => day.id === dayFilter)?.day_index ?? 0) + 1}`;

  return (
    <aside className="map-pane" aria-label="Trip map">
      <div className="map-pane__header">
        <div>
          <p className="map-pane__eyebrow"><Layers3 size={13} /> The route</p>
          <h2>{dayLabel}</h2>
        </div>
        <button type="button" className="button button--secondary button--small" onClick={fit} disabled={!filtered.length}>
          <Expand size={14} /> Fit {dayFilter === null ? "all" : "day"}
        </button>
      </div>

      {(daysWithPlaces.length > 1 || places.some((place) => !place.day_id)) && (
        <div className="map-pane__filters" role="group" aria-label="Filter the map by day">
        <button type="button" className={dayFilter === null ? "is-active" : ""} onClick={() => { setDayFilter(null); onFocusDay(null); }}>
          All
        </button>
        {daysWithPlaces.map((day) => (
          <button
            type="button"
            key={day.id}
            className={dayFilter === day.id ? "is-active" : ""}
            onClick={() => { setDayFilter(day.id); onFocusDay(day.id); }}
          >
            Day {day.day_index + 1}
          </button>
        ))}
        {places.some((place) => !place.day_id) && (
          <button
            type="button"
            className={dayFilter === "unscheduled" ? "is-active" : ""}
            onClick={() => { setDayFilter("unscheduled"); onFocusDay(null); }}
          >
            Ideas
          </button>
        )}
        </div>
      )}

      <div className="map-pane__canvas">
        <div ref={containerRef} className={`map-canvas ${theme.resolved === "dark" ? "map-canvas--dark" : ""}`} />
        {!allPinned.length && (
          <div className="map-pane__empty">
            <span><MapPinOff size={22} /></span>
            <strong>No pins yet</strong>
            <p>Add a place with an address or coordinates and it will appear on the map.</p>
          </div>
        )}
        {allPinned.length > 0 && !filtered.length && (
          <div className="map-pane__empty">
            <span><MapPinOff size={22} /></span>
            <strong>No pins in this view</strong>
            <p>Try another day, or add a stop with coordinates.</p>
          </div>
        )}
      </div>

      <div className="map-pane__footer">
        <span>{filtered.length} {filtered.length === 1 ? "pin" : "pins"} on the map</span>
        <span className="map-pane__osm">OpenStreetMap</span>
      </div>
    </aside>
  );
}
