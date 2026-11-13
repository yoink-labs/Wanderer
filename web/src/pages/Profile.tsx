import { Check, ChevronRight, LogOut, Monitor, Moon, Save, Sun, Trash2, UserRound } from "lucide-react";
import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { useSession } from "../auth/session";
import { Avatar } from "../components/Avatar";
import { ConfirmDialog } from "../components/Dialog";
import { ErrorState, PageLoader } from "../components/States";
import { useToast } from "../components/Toast";
import { useTheme, type ThemePreference } from "../lib/theme";
import type { Profile as ProfileRecord } from "../types";

const CURRENCIES = ["USD", "EUR", "GBP", "JPY", "CAD", "AUD", "CHF", "SEK", "NOK", "DKK", "ISK", "MXN", "BRL", "SGD", "THB", "INR", "KRW", "CNY", "NZD"];
const LANGUAGES = [
  { value: "en", label: "English" },
  { value: "es", label: "Español" },
  { value: "fr", label: "Français" },
  { value: "de", label: "Deutsch" },
  { value: "pt", label: "Português" },
  { value: "ja", label: "日本語" },
];

export default function Profile() {
  const session = useSession();
  const theme = useTheme();
  const navigate = useNavigate();
  const { toast } = useToast();
  const [profile, setProfile] = useState<ProfileRecord | null>(null);
  const [loading, setLoading] = useState(session.isSignedIn);
  const [error, setError] = useState<string | null>(null);
  const [name, setName] = useState("");
  const [currency, setCurrency] = useState("USD");
  const [units, setUnits] = useState("metric");
  const [locale, setLocale] = useState("en");
  const [saving, setSaving] = useState(false);
  const [deleteOpen, setDeleteOpen] = useState(false);
  const [deleting, setDeleting] = useState(false);

  async function load() {
    if (!session.isSignedIn) {
      setLoading(false);
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const result = await session.api.me();
      setProfile(result);
      setName(result.display_name ?? "");
      setCurrency(result.currency ?? "USD");
      setUnits(result.units ?? "metric");
      setLocale(result.locale ?? "en");
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Couldn't load your profile.");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void load();
  }, [session.api, session.isSignedIn]); // eslint-disable-line react-hooks/exhaustive-deps

  async function save() {
    if (!name.trim()) {
      toast("Your name can't be empty.", "error");
      return;
    }
    setSaving(true);
    try {
      const updated = await session.api.updateMe({ display_name: name.trim(), currency, units, locale });
      setProfile(updated);
      localStorage.setItem("wanderer.currency", currency);
      toast("Profile saved", "success");
    } catch (caught) {
      toast(caught instanceof Error ? caught.message : "Couldn't save your profile.", "error");
    } finally {
      setSaving(false);
    }
  }

  async function signOut() {
    if (session.isTest) {
      toast("Test auth is fixed by VITE_USE_TEST_AUTH. Remove it to use the Clerk sign-in flow.", "info");
      return;
    }
    try {
      await session.signOut();
    } catch {
      toast("Couldn't sign out. Try again.", "error");
    }
  }

  async function deleteAccount() {
    setDeleting(true);
    try {
      await session.api.deleteMe();
      toast("Your account and its trips have been deleted.", "success");
      setDeleteOpen(false);
      if (session.isTest) {
        navigate("/");
      } else {
        await session.signOut();
      }
    } catch (caught) {
      toast(caught instanceof Error ? caught.message : "Couldn't delete your account.", "error");
    } finally {
      setDeleting(false);
    }
  }

  if (!session.isSignedIn) {
    return (
      <div className="page-shell page-shell--narrow profile-guest">
        <div className="profile-guest__card">
          <span className="profile-guest__art" aria-hidden="true"><UserRound size={32} /></span>
          <p className="context-line">Your account</p>
          <h1>Keep your trips close.</h1>
          <p>Sign in to sync trips across devices, invite the people coming with you, and keep a private layer of plans.</p>
          <button type="button" className="button button--primary button--large" onClick={session.signIn}>
            Sign in or create an account
          </button>
          <p className="quiet-note">Guest trips on this device will be copied in the next time you sign in.</p>
          <Link to="/" className="text-link">Back to your trips <ChevronRight size={14} /></Link>
        </div>
      </div>
    );
  }

  if (loading) return <div className="page-shell"><PageLoader label="Loading your profile" /></div>;
  if (error || !profile) {
    return (
      <div className="page-shell page-shell--narrow">
        <ErrorState title="Couldn't load your profile" message={error ?? undefined} onRetry={() => void load()} />
      </div>
    );
  }

  const displayName = name || profile.display_name || session.user?.displayName || "Traveler";
  const email = profile.email ?? session.user?.email;

  return (
    <div className="page-shell profile-page">
      <header className="profile-heading">
        <div className="profile-heading__identity">
          <Avatar name={displayName} src={profile.avatar_url ?? session.user?.avatarUrl} size="lg" />
          <div>
            <p className="context-line">Your account</p>
            <h1>{displayName}</h1>
            <p>{email || "No email on this profile"}</p>
          </div>
        </div>
        <div className="profile-heading__chips">
          {session.isTest && <span className="status-chip status-chip--test">Test session</span>}
          <Link to="/" className="text-link">Back to trips <ChevronRight size={14} /></Link>
        </div>
      </header>

      {session.isTest && (
        <div className="notice">
          <span className="notice__dot" />
          <div>
            <strong>Local test sign-in is active</strong>
            <p>Requests are using a test bearer token against {import.meta.env.VITE_API_URL || "http://127.0.0.1:8787"}. Production uses Clerk, so sign-out is disabled in this mode.</p>
          </div>
        </div>
      )}

      <div className="profile-grid">
        <section className="profile-card">
          <div className="section-heading section-heading--compact">
            <div>
              <h2>Your details</h2>
              <p className="quiet-note">How you show up on shared trips.</p>
            </div>
          </div>
          <form
            className="profile-form"
            onSubmit={(event) => {
              event.preventDefault();
              void save();
            }}
          >
            <label className="field">
              <span className="field__label">Display name</span>
              <input value={name} onChange={(event) => setName(event.target.value)} autoComplete="name" />
            </label>
            <label className="field">
              <span className="field__label">Email</span>
              <input value={email ?? ""} readOnly />
              <span className="field__hint">Managed by your sign-in provider.</span>
            </label>
            <div className="field-row">
              <label className="field">
                <span className="field__label">Currency</span>
                <select value={currency} onChange={(event) => setCurrency(event.target.value)}>
                  {CURRENCIES.map((code) => <option value={code} key={code}>{code}</option>)}
                </select>
              </label>
              <label className="field">
                <span className="field__label">Units</span>
                <select value={units} onChange={(event) => setUnits(event.target.value)}>
                  <option value="metric">Metric</option>
                  <option value="imperial">Imperial</option>
                </select>
              </label>
            </div>
            <label className="field">
              <span className="field__label">Language</span>
              <select value={locale} onChange={(event) => setLocale(event.target.value)}>
                {LANGUAGES.map((language) => <option value={language.value} key={language.value}>{language.label}</option>)}
              </select>
            </label>
            <div className="profile-form__actions">
              <button type="submit" className="button button--primary" disabled={saving}>
                <Save size={16} /> {saving ? "Saving…" : "Save changes"}
              </button>
              {savedMatches(profile, name, currency, units, locale) && <span className="saved-note"><Check size={14} /> Up to date</span>}
            </div>
          </form>
        </section>

        <section className="profile-card">
          <div className="section-heading section-heading--compact">
            <div>
              <h2>Appearance</h2>
              <p className="quiet-note">The atlas comes in two lights.</p>
            </div>
          </div>
          <div className="appearance-options" role="radiogroup" aria-label="Appearance">
            {([
              { value: "system" as ThemePreference, label: "System", icon: <Monitor size={17} /> },
              { value: "light" as ThemePreference, label: "Light", icon: <Sun size={17} /> },
              { value: "dark" as ThemePreference, label: "Dark", icon: <Moon size={17} /> },
            ]).map((option) => (
              <button
                type="button"
                key={option.value}
                role="radio"
                aria-checked={theme.preference === option.value}
                className={`appearance-option ${theme.preference === option.value ? "is-active" : ""}`}
                onClick={() => theme.setPreference(option.value)}
              >
                <span className="appearance-option__swatch" data-theme-preview={option.value}>
                  {option.icon}
                </span>
                {option.label}
                {theme.preference === option.value && <Check size={15} className="appearance-option__check" />}
              </button>
            ))}
          </div>
          <div className="preference-note">
            <p><strong>Currency</strong> sets the default for new trips.</p>
            <p><strong>Units</strong> applies to distances shown around the app.</p>
          </div>

          <div className="account-actions">
            <button type="button" className="button button--secondary" onClick={() => void signOut()}>
              <LogOut size={16} /> Sign out
            </button>
            <button type="button" className="button button--danger-quiet" onClick={() => setDeleteOpen(true)}>
              <Trash2 size={16} /> Delete account
            </button>
          </div>
        </section>
      </div>

      <ConfirmDialog
        open={deleteOpen}
        onClose={() => setDeleteOpen(false)}
        onConfirm={deleteAccount}
        title="Delete your Wanderer account?"
        message="This removes your profile, every trip you own, and all their days, places, bookings, expenses and invites. Trips you joined as a member stay with their owners. This can't be undone."
        confirmLabel="Delete everything"
        destructive
        busy={deleting}
      />
    </div>
  );
}

function savedMatches(profile: ProfileRecord, name: string, currency: string, units: string, locale: string): boolean {
  return (
    (profile.display_name ?? "") === name.trim() &&
    profile.currency === currency &&
    profile.units === units &&
    profile.locale === locale
  );
}
