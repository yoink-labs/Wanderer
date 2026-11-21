import { Compass, Moon, Sun } from "lucide-react";
import { Link, NavLink } from "react-router-dom";
import { useSession } from "../auth/session";
import { useTheme } from "../lib/theme";
import { Avatar } from "./Avatar";
import { Logo } from "./Logo";

/** Where tipping is explained. The page says which apps take tips and how. */
export const TIP_URL = "https://yoinklabs.dev/tip";

/** The pink "Tip the devs" pill shared by every Yoink Labs web app. */
export function TipPill() {
  return (
    <a
      href={TIP_URL}
      className="tip-pill"
      aria-label="Tip the devs"
      title="Optional tips. They unlock nothing."
    >
      <svg
        className="tip-pill__heart"
        viewBox="0 0 24 24"
        width="14"
        height="14"
        aria-hidden="true"
        focusable="false"
      >
        <path
          fill="currentColor"
          d="M12 21.35 10.55 20.03C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35Z"
        />
      </svg>
      <span>Tip the devs</span>
    </a>
  );
}

export function AppHeader() {
  const session = useSession();
  const theme = useTheme();
  const displayName = session.user?.displayName ?? "Guest";

  return (
    <header className="site-header">
      <div className="site-header__inner">
        <Link to="/" className="site-header__brand" aria-label="Wanderer home">
          <Logo />
        </Link>

        <nav className="site-nav" aria-label="Primary">
          <NavLink to="/" end className={({ isActive }) => (isActive ? "site-nav__link is-active" : "site-nav__link")}>
            Trips
          </NavLink>
          <NavLink to="/guides" className={({ isActive }) => (isActive ? "site-nav__link is-active" : "site-nav__link")}>
            Guides
          </NavLink>
        </nav>

        <div className="site-header__actions">
          <Link to="/about" className="header-about">Made for the journey</Link>
          <TipPill />
          <button
            type="button"
            className="icon-button icon-button--quiet theme-toggle"
            onClick={theme.toggle}
            aria-label={`Use ${theme.resolved === "dark" ? "light" : "dark"} appearance`}
            title={`Use ${theme.resolved === "dark" ? "light" : "dark"} appearance`}
          >
            {theme.resolved === "dark" ? <Sun size={18} /> : <Moon size={18} />}
          </button>

          {session.isSignedIn ? (
            <Link to="/profile" className="site-header__account" aria-label={`Profile for ${displayName}`}>
              <Avatar name={displayName} src={session.user?.avatarUrl} size="sm" />
              <span className="site-header__account-label">{displayName.split(" ")[0]}</span>
            </Link>
          ) : (
            <Link to="/sign-in" className="button button--ink button--small">
              Sign in
            </Link>
          )}
        </div>
      </div>
    </header>
  );
}

export function GuestMark() {
  return (
    <span className="guest-mark">
      <Compass size={13} aria-hidden="true" />
      Guest planning
    </span>
  );
}
