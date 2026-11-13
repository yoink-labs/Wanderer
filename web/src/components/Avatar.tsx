import { initials } from "../lib/format";

interface AvatarProps {
  name: string | null | undefined;
  src?: string | null;
  size?: "sm" | "md" | "lg";
  className?: string;
}

export function Avatar({ name, src, size = "md", className = "" }: AvatarProps) {
  const label = name?.trim() || "Traveler";
  return (
    <span className={`avatar avatar--${size} ${className}`.trim()} aria-label={label} title={label}>
      {src ? <img src={src} alt="" /> : initials(label)}
    </span>
  );
}

export function AvatarStack({ names, max = 4 }: { names: Array<string | null | undefined>; max?: number }) {
  const visible = names.slice(0, max);
  const extra = names.length - visible.length;
  return (
    <span className="avatar-stack" aria-label={`${names.length} travellers`}>
      {visible.map((name, index) => (
        <Avatar key={`${name}-${index}`} name={name} size="sm" />
      ))}
      {extra > 0 && <span className="avatar avatar--sm avatar--extra">+{extra}</span>}
    </span>
  );
}
