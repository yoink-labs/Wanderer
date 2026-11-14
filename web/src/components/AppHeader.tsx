import { Compass, Moon, Sun } from "lucide-react";
import { Link, NavLink } from "react-router-dom";
import { useSession } from "../auth/session";
import { useTheme } from "../lib/theme";
import { Avatar } from "./Avatar";
import { Logo } from "./Logo";

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
            <button type="button" className="button button--ink button--small" onClick={session.signIn} disabled={!session.isLoaded}>
              Sign in
            </button>
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
