export function money(amount: number, currency = "USD", options: { maximumFractionDigits?: number } = {}): string {
  const value = Number.isFinite(amount) ? amount : 0;
  try {
    return new Intl.NumberFormat(undefined, {
      style: "currency",
      currency: currency || "USD",
      maximumFractionDigits: options.maximumFractionDigits ?? (Math.abs(value % 1) < 0.005 ? 0 : 2),
    }).format(value);
  } catch {
    return `${currency} ${value.toFixed(2)}`;
  }
}

export function initials(name: string | null | undefined, fallback = "W"): string {
  const clean = (name ?? "").trim();
  if (!clean) return fallback;
  const words = clean.split(/[\s._-]+/).filter(Boolean);
  if (words.length === 1) return words[0].slice(0, 2).toUpperCase();
  return words.slice(0, 2).map((word) => word[0]).join("").toUpperCase();
}

export function plural(count: number, singular: string, pluralForm = `${singular}s`): string {
  return `${count} ${count === 1 ? singular : pluralForm}`;
}

export function summaryName(name: string | null | undefined, email: string | null | undefined): string {
  return name?.trim() || email?.split("@")[0] || "Traveler";
}

export function safeUrl(value: string | null | undefined): string | null {
  if (!value) return null;
  try {
    const url = new URL(value);
    if (url.protocol === "http:" || url.protocol === "https:") return url.toString();
  } catch {
    // not a URL
  }
  return null;
}

export function displayDomain(value: string | null | undefined): string {
  const url = safeUrl(value);
  if (!url) return value || "";
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch {
    return value || "";
  }
}

export const categoryLabels: Record<string, string> = {
  sight: "Sight",
  food: "Food",
  lodging: "Stay",
  activity: "Activity",
  transport: "Transport",
  shopping: "Shopping",
  note: "Note",
  flight: "Flight",
  car: "Car",
  restaurant: "Restaurant",
  train: "Train",
  other: "Other",
  activities: "Activities",
};
