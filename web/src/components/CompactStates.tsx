import { AlertCircle, LoaderCircle, RefreshCw } from "lucide-react";

export function PageLoader({ label = "Loading" }: { label?: string }) {
  return (
    <div className="page-loader" role="status">
      <LoaderCircle size={22} className="spin" aria-hidden="true" />
      <span>{label}…</span>
    </div>
  );
}

export function ErrorState({ title, message, onRetry }: { title?: string; message?: string; onRetry?: () => void }) {
  return (
    <div className="state-card state-card--error" role="alert">
      <span className="state-card__icon"><AlertCircle size={24} /></span>
      <div>
        <h2>{title ?? "Something went wrong"}</h2>
        {message && <p>{message}</p>}
      </div>
      {onRetry && (
        <button type="button" className="button button--secondary" onClick={onRetry}>
          <RefreshCw size={16} /> Try again
        </button>
      )}
    </div>
  );
}
