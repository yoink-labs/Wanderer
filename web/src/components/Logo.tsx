export function Logo({ compact = false }: { compact?: boolean }) {
  return (
    <span className={`logo${compact ? " logo--compact" : ""}`} aria-label="Wanderer">
      <svg className="logo__mark" viewBox="0 0 42 32" aria-hidden="true">
        <path d="M3 23.5c6.8-15 12.8-15.5 19.1-4.2 4.4 8 8.2 4.5 10.1-2.5" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" />
        <circle cx="33.5" cy="15" r="3.4" fill="var(--route)" />
      </svg>
      {!compact && <span className="logo__word">Wanderer</span>}
    </span>
  );
}
