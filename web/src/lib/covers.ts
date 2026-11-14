export interface CoverPalette {
  name: string;
  deep: string;
  mid: string;
  light: string;
  ink: string;
  accent: string;
}

const PALETTES: CoverPalette[] = [
  { name: "Aegean", deep: "#173F52", mid: "#2C6E8F", light: "#D6E5E7", ink: "#F6EFE4", accent: "#F2A922" },
  { name: "Lagoon", deep: "#143D34", mid: "#1E8A6E", light: "#D6E8DD", ink: "#F5EFE2", accent: "#F2A922" },
  { name: "Dusk", deep: "#2A2638", mid: "#66617A", light: "#DEDCE5", ink: "#F7EEDE", accent: "#F2A922" },
  { name: "Ochre", deep: "#69421A", mid: "#B77A26", light: "#F6E4BF", ink: "#FFF8E9", accent: "#10283A" },
  { name: "Clay", deep: "#552E25", mid: "#9B5541", light: "#EEDCD5", ink: "#FFF6EB", accent: "#F2A922" },
  { name: "Pine", deep: "#1D3128", mid: "#506D57", light: "#DCE6DA", ink: "#F7F0E3", accent: "#F2A922" },
  { name: "Harbor", deep: "#1D2C37", mid: "#3E6275", light: "#D9E4E7", ink: "#FFF8EE", accent: "#F2A922" },
];

function hashString(value: string): number {
  let hash = 0;
  for (let index = 0; index < value.length; index += 1) {
    hash = (hash * 31 + value.charCodeAt(index)) >>> 0;
  }
  return hash;
}

export function coverPalette(seed: string): CoverPalette {
  return PALETTES[hashString(seed) % PALETTES.length];
}

export function coverStyle(seed: string): React.CSSProperties {
  const palette = coverPalette(seed);
  return {
    "--cover-deep": palette.deep,
    "--cover-mid": palette.mid,
    "--cover-light": palette.light,
    "--cover-ink": palette.ink,
    "--cover-accent": palette.accent,
  } as React.CSSProperties;
}

export function coverVariant(seed: string): number {
  return hashString(seed) % 4;
}
