import { coverPalette, coverStyle, coverVariant } from "../lib/covers";

interface CoverArtProps {
  seed: string;
  destination?: string | null;
  imageUrl?: string | null;
  className?: string;
  variant?: "hero" | "card" | "rail" | "guide";
  showMark?: boolean;
}

export function CoverArt({ seed, destination, imageUrl, className = "", variant = "card", showMark = true }: CoverArtProps) {
  const palette = coverPalette(seed);
  const artVariant = coverVariant(seed);
  return (
    <span className={`cover-art cover-art--${variant} cover-art--v${artVariant} ${className}`.trim()} style={coverStyle(seed)} aria-hidden="true">
      {imageUrl ? (
        <img
          src={imageUrl}
          alt=""
          className="cover-art__photo"
          loading="lazy"
          onError={(event) => {
            event.currentTarget.style.display = "none";
          }}
        />
      ) : null}
      <svg className="cover-art__topography" viewBox="0 0 600 400" preserveAspectRatio="xMidYMid slice">
        <g fill="none" stroke="currentColor" strokeWidth="1">
          <path d="M-40 92c77-71 166-91 265-53 76 29 130 20 184-20s126-39 232 5" />
          <path d="M-55 131c92-61 188-75 276-37 72 31 135 19 202-26s138-33 232 10" />
          <path d="M-64 173c97-55 197-63 292-22 82 35 145 16 216-30s146-29 224 10" />
          <path d="M-72 221c104-53 207-55 308-9 85 39 159 16 231-31s151-21 220 19" />
          <path d="M-30 402c34-91 139-122 259-146 139-28 240 42 402 3" />
          <path d="M-65 400c49-109 166-145 300-166 145-22 230 59 416 23" />
          <path d="M116 399c-4-55 34-92 84-101 67-12 103 32 84 74-15 32-61 40-90 16" />
          <path d="M145 399c-4-38 22-64 57-70 45-8 74 22 59 52-11 22-43 28-63 10" />
          <path d="M420 398c2-79 54-127 122-118 52 7 77 56 51 91-25 33-78 33-96-5" />
        </g>
      </svg>
      <span className="cover-art__wash" />
      <span className="cover-art__route">
        <svg viewBox="0 0 600 400" preserveAspectRatio="none">
          <path d="M-20 315C95 270 126 201 223 216s102 77 188 28 94-91 212-85" fill="none" stroke="var(--route)" strokeWidth="2" strokeDasharray="1 0" />
          <circle cx="222" cy="216" r="4" fill="var(--route)" />
          <circle cx="410" cy="244" r="3" fill="var(--route)" opacity=".55" />
        </svg>
      </span>
      {destination && <span className="cover-art__ghost-word">{destination.split(",")[0]}</span>}
      <span className="cover-art__coordinates">
        <span>{String.fromCharCode(65 + (seed.charCodeAt(0) % 26))}{String(10 + (seed.charCodeAt(1) % 80))}°</span>
        <span>{String.fromCharCode(65 + (seed.charCodeAt(2) % 26))}{String(10 + (seed.charCodeAt(3) % 80))}°</span>
      </span>
      {showMark && (
        <span className="cover-art__mark">
          <span style={{ background: palette.accent }} />
          <span style={{ background: palette.ink }} />
        </span>
      )}
    </span>
  );
}
