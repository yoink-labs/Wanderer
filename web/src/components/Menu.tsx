import { MoreHorizontal } from "lucide-react";
import { useEffect, useLayoutEffect, useRef, useState, type ReactNode } from "react";
import { createPortal } from "react-dom";

export type MenuEntry =
  | {
      label: string;
      icon?: ReactNode;
      detail?: string;
      onSelect: () => void;
      danger?: boolean;
      disabled?: boolean;
    }
  | { separator: true };

interface MenuProps {
  entries: MenuEntry[];
  label?: string;
  trigger?: ReactNode;
  triggerClassName?: string;
  align?: "start" | "end";
}

export function Menu({ entries, label = "More actions", trigger, triggerClassName = "icon-button icon-button--quiet", align = "end" }: MenuProps) {
  const [open, setOpen] = useState(false);
  const [position, setPosition] = useState<{ top: number; left: number; width: number } | null>(null);
  const buttonRef = useRef<HTMLButtonElement>(null);
  const menuRef = useRef<HTMLDivElement>(null);

  useLayoutEffect(() => {
    if (!open) return;
    const update = () => {
      const triggerRect = buttonRef.current?.getBoundingClientRect();
      if (!triggerRect) return;
      const width = 226;
      const estimatedHeight = Math.min(420, entries.length * 46 + 16);
      let left = align === "end" ? triggerRect.right - width : triggerRect.left;
      left = Math.max(10, Math.min(left, window.innerWidth - width - 10));
      let top = triggerRect.bottom + 8;
      if (top + estimatedHeight > window.innerHeight - 10) {
        top = Math.max(10, triggerRect.top - estimatedHeight - 8);
      }
      setPosition({ top, left, width });
    };
    update();
    window.addEventListener("resize", update);
    window.addEventListener("scroll", update, true);
    return () => {
      window.removeEventListener("resize", update);
      window.removeEventListener("scroll", update, true);
    };
  }, [align, entries.length, open]);

  useEffect(() => {
    if (!open) return;
    const close = (event: PointerEvent) => {
      const target = event.target as Node;
      if (!buttonRef.current?.contains(target) && !menuRef.current?.contains(target)) setOpen(false);
    };
    const key = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setOpen(false);
        buttonRef.current?.focus();
      }
    };
    document.addEventListener("pointerdown", close);
    document.addEventListener("keydown", key);
    const timer = window.setTimeout(() => {
      menuRef.current?.querySelector<HTMLButtonElement>("button:not(:disabled)")?.focus();
    }, 20);
    return () => {
      document.removeEventListener("pointerdown", close);
      document.removeEventListener("keydown", key);
      window.clearTimeout(timer);
    };
  }, [open]);

  return (
    <>
      <button
        ref={buttonRef}
        type="button"
        className={triggerClassName}
        aria-haspopup="menu"
        aria-expanded={open}
        aria-label={label}
        title={label}
        onClick={() => setOpen((current) => !current)}
      >
        {trigger ?? <MoreHorizontal size={18} />}
      </button>
      {open && position
        ? createPortal(
            <div
              ref={menuRef}
              className="action-menu"
              role="menu"
              aria-label={label}
              style={{ top: position.top, left: position.left, width: position.width }}
            >
              {entries.map((entry, index) =>
                "separator" in entry ? (
                  <div className="action-menu__separator" role="separator" key={`sep-${index}`} />
                ) : (
                  <button
                    type="button"
                    role="menuitem"
                    className={`action-menu__item ${entry.danger ? "is-danger" : ""}`.trim()}
                    key={`${entry.label}-${index}`}
                    onClick={() => {
                      setOpen(false);
                      entry.onSelect();
                    }}
                    disabled={entry.disabled}
                  >
                    {entry.icon && <span className="action-menu__icon">{entry.icon}</span>}
                    <span className="action-menu__copy">
                      <span>{entry.label}</span>
                      {entry.detail && <small>{entry.detail}</small>}
                    </span>
                  </button>
                ),
              )}
            </div>,
            document.body,
          )
        : null}
    </>
  );
}
