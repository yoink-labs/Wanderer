import {
  BedDouble,
  Building2,
  CarFront,
  Coffee,
  Landmark,
  MapPin,
  Plane,
  ShoppingBag,
  StickyNote,
  Ticket,
  TrainFront,
  UserRound,
  UtensilsCrossed,
} from "lucide-react";
import type { PlaceCategory, ReservationType, TripRole } from "../types";

export function PlaceCategoryIcon({ category, size = 16 }: { category: PlaceCategory; size?: number }) {
  switch (category) {
    case "food": return <UtensilsCrossed size={size} />;
    case "lodging": return <BedDouble size={size} />;
    case "activity": return <Ticket size={size} />;
    case "transport": return <TrainFront size={size} />;
    case "shopping": return <ShoppingBag size={size} />;
    case "note": return <StickyNote size={size} />;
    default: return <Landmark size={size} />;
  }
}

export function ReservationTypeIcon({ type, size = 16 }: { type: ReservationType; size?: number }) {
  switch (type) {
    case "flight": return <Plane size={size} />;
    case "lodging": return <BedDouble size={size} />;
    case "car": return <CarFront size={size} />;
    case "restaurant": return <Coffee size={size} />;
    case "train": return <TrainFront size={size} />;
    default: return <Ticket size={size} />;
  }
}

export function OnlyYouBadge({ label = "Only you", title = "Only you can see this item" }: { label?: string; title?: string }) {
  return (
    <span className="only-you-badge" title={title}>
      <UserRound size={12} aria-hidden="true" />
      {label}
    </span>
  );
}

export function RoleBadge({ role }: { role: TripRole | null }) {
  if (!role) return null;
  if (role === "viewer") return <span className="role-badge role-badge--viewer"><UserRound size={12} /> View only</span>;
  if (role === "editor") return <span className="role-badge">Can edit</span>;
  return <span className="role-badge">Owner</span>;
}

export function SmallMapGlyph() {
  return <MapPin size={14} />;
}

export function BuildingGlyph() {
  return <Building2 size={14} />;
}
