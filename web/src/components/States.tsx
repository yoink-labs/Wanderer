import { AlertCircle, ArrowRight, Compass, LoaderCircle, RefreshCw } from "lucide-react";
import type { ReactNode } from "react";

export function PageLoader({ label = "Loading" }: { label?: string }) {
  return (
    <div className="page-loader" role="status">
      <LoaderCircle size={22} className="spin" aria-hidden="true" />
      <span>{label}…</span>
    </div>
  );
}

export function ErrorState({
  title = "Something went wrong",
  message,
  onRetry,
  retryLabel = "Try again",
}: {
  title?: string;
  message?: string;
  onRetry?: () => void;
  retryLabel?: string;
}) {
  return (
    <div className="state-card state-card--error" role="alert">
      <span className="state-card__icon"><AlertCircle size={24} /></span>
      <div>
        <h2>{title}</h2>
        {message && <p>{message}</p>}
      </div>
      {onRetry && (
        <button type="button" className="button button--secondary" onClick={onRetry}>
          <RefreshCw size={16} /> {retryLabel}
        </button>
      )}
    </div>
  );
}

export function EmptyState({
  title,
  message,
  action,
  icon,
}: {
  title: string;
  message: string;
  action?: { label: string; onClick: () => void };
  icon?: ReactNode;
}) {
  return (
    <div className="state-card state-card--empty">
      <span className="state-card__icon">{icon ?? <Compass size={24} />}</span>
      <div>
        <h2>{title}</h2>
        <p>{message}</p>
      </div>
      {action && (
        <button type="button" className="button button--primary" onClick={action.onClick}>
          {action.label} <ArrowRight size={16} />
        </button>
      )}
    </div>
  );
}

export function Skeleton({ width, height, circle = false, className = "" }: { width?: string; height?: string; circle?: boolean; className?: string }) {
  return (
    <span
      className={`skeleton ${circle ? "skeleton--circle" : ""} ${className}`.trim()}
      style={{ width, height }}
      aria-hidden="true"
    />
  );
}

export function HomeSkeleton() {
  return (
    <div className="home-skeleton" aria-hidden="true">
      <div className="home-skeleton__hero">
        <Skeleton height="100%" className="home-skeleton__cover" />
        <div className="home-skeleton__lines">
          <Skeleton width="24%" height="12px" />
          <Skeleton width="78%" height="54px" />
          <Skeleton width="42%" height="18px" />
        </div>
      </div>
      <div className="trip-ledger">
        {[0, 1, 2].map((item) => (
          <div className="trip-ledger__row" key={item}>
            <Skeleton width="72px" height="72px" />
            <div className="home-skeleton__lines">
              <Skeleton width="40%" height="16px" />
              <Skeleton width="26%" height="12px" />
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

export function TripSkeleton() {
  return (
    <div className="workspace-skeleton" aria-label="Loading trip" role="status">
      <aside className="workspace-skeleton__rail">
        <Skeleton width="70%" height="12px" />
        {[0, 1, 2, 3].map((item) => (
          <Skeleton height="58px" key={item} />
        ))}
      </aside>
      <div className="workspace-skeleton__main">
        <Skeleton width="34%" height="18px" />
        {[0, 1, 2].map((item) => (
          <div className="workspace-skeleton__stop" key={item}>
            <Skeleton circle width="34px" height="34px" />
            <div className="home-skeleton__lines">
              <Skeleton width="55%" height="16px" />
              <Skeleton width="34%" height="12px" />
            </div>
          </div>
        ))}
      </div>
      <div className="workspace-skeleton__map">
        <Skeleton height="100%" />
      </div>
    </div>
  );
}

export function InlineSpinner({ label = "Saving" }: { label?: string }) {
  return (
    <span className="inline-spinner" role="status">
      <LoaderCircle size={14} className="spin" aria-hidden="true" /> {label}…
    </span>
  );
}
