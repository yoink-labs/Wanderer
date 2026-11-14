import { AlertTriangle, CheckCircle2, Info, X } from "lucide-react";
import { createContext, useCallback, useContext, useRef, useState, type ReactNode } from "react";
import { createPortal } from "react-dom";

type ToastTone = "info" | "success" | "error";
interface ToastItem {
  id: number;
  message: string;
  tone: ToastTone;
}

interface ToastValue {
  toast: (message: string, tone?: ToastTone) => void;
}

const ToastContext = createContext<ToastValue | null>(null);

export function useToast(): ToastValue {
  const value = useContext(ToastContext);
  if (!value) throw new Error("useToast must be used inside ToastProvider");
  return value;
}

export function ToastProvider({ children }: { children: ReactNode }) {
  const [items, setItems] = useState<ToastItem[]>([]);
  const counter = useRef(0);

  const dismiss = useCallback((id: number) => {
    setItems((current) => current.filter((item) => item.id !== id));
  }, []);

  const toast = useCallback(
    (message: string, tone: ToastTone = "info") => {
      counter.current += 1;
      const id = counter.current;
      setItems((current) => [...current.slice(-3), { id, message, tone }]);
      window.setTimeout(() => dismiss(id), 4600);
    },
    [dismiss],
  );

  return (
    <ToastContext.Provider value={{ toast }}>
      {children}
      {createPortal(
        <div className="toast-stack" aria-live="polite" aria-atomic="false">
          {items.map((item) => (
            <div className={`toast toast--${item.tone}`} key={item.id} role="status">
              {item.tone === "success" ? (
                <CheckCircle2 size={18} aria-hidden="true" />
              ) : item.tone === "error" ? (
                <AlertTriangle size={18} aria-hidden="true" />
              ) : (
                <Info size={18} aria-hidden="true" />
              )}
              <span>{item.message}</span>
              <button type="button" className="toast__close" onClick={() => dismiss(item.id)} aria-label="Dismiss message">
                <X size={14} />
              </button>
            </div>
          ))}
        </div>,
        document.body,
      )}
    </ToastContext.Provider>
  );
}
