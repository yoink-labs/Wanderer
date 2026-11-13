import { Check, Copy, ExternalLink, Link2, Mail, RefreshCw, Send, Trash2, UserPlus, Users } from "lucide-react";
import { useEffect, useState } from "react";
import { useSession } from "../auth/session";
import { Avatar } from "../components/Avatar";
import { ConfirmDialog } from "../components/Dialog";
import { useToast } from "../components/Toast";
import { API_URL, shareUrl } from "../lib/api";
import { fmtDate } from "../lib/dates";
import { summaryName } from "../lib/format";
import type { Invite, Member } from "../types";
import type { TripStore } from "./useTripStore";

export function ShareView({ store }: { store: TripStore }) {
  const session = useSession();
  const { toast } = useToast();
  const trip = store.bundle?.trip;
  const members = store.bundle?.members ?? [];
  const [token, setToken] = useState(trip?.share_token ?? null);
  const [invites, setInvites] = useState<Invite[]>([]);
  const [invitesError, setInvitesError] = useState<string | null>(null);
  const [email, setEmail] = useState("");
  const [role, setRole] = useState<"editor" | "viewer">("editor");
  const [inviting, setInviting] = useState(false);
  const [inviteError, setInviteError] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  const [regenerateOpen, setRegenerateOpen] = useState(false);
  const [regenerating, setRegenerating] = useState(false);
  const [pendingRemove, setPendingRemove] = useState<Invite | null>(null);
  const [removing, setRemoving] = useState(false);

  useEffect(() => {
    setToken(trip?.share_token ?? null);
  }, [trip?.share_token]);

  useEffect(() => {
    if (!session.isSignedIn || store.isGuest) return;
    let cancelled = false;
    session.api
      .invites(store.tripId)
      .then((rows) => {
        if (!cancelled) setInvites(rows);
      })
      .catch((caught) => {
        if (!cancelled) setInvitesError(caught instanceof Error ? caught.message : "Invites couldn't load.");
      });
    return () => {
      cancelled = true;
    };
  }, [session.api, session.isSignedIn, store.isGuest, store.tripId]);

  const publicLink = shareUrl(token);
  const owner = store.role === "owner";
  const canInvite = store.canWrite && !store.isGuest;

  async function copy(text: string, message = "Link copied") {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
      toast(message, "success");
      window.setTimeout(() => setCopied(false), 2200);
    } catch {
      toast("Couldn't copy automatically. Select the link and copy it.", "error");
    }
  }

  async function regenerate() {
    setRegenerating(true);
    try {
      const result = await session.api.shareLink(store.tripId);
      setToken(result.share_token);
      setRegenerateOpen(false);
      toast("New share link created. The old link no longer works.", "success");
    } catch (caught) {
      toast(caught instanceof Error ? caught.message : "Couldn't create a new link.", "error");
    } finally {
      setRegenerating(false);
    }
  }

  async function invite(event: React.FormEvent) {
    event.preventDefault();
    setInviteError(null);
    const clean = email.trim().toLowerCase();
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(clean)) {
      setInviteError("Enter a valid email address.");
      return;
    }
    setInviting(true);
    try {
      const created = await session.api.invite(store.tripId, clean, role);
      setInvites((current) => [created, ...current.filter((item) => item.id !== created.id)]);
      setEmail("");
      toast(created.email_delivered ? `Invite sent to ${clean}` : "Invite saved. Email delivery isn't configured, so share the invite link directly.", created.email_delivered ? "success" : "info");
    } catch (caught) {
      setInviteError(caught instanceof Error ? caught.message : "Couldn't send the invite.");
    } finally {
      setInviting(false);
    }
  }

  async function removeInvite() {
    if (!pendingRemove) return;
    setRemoving(true);
    try {
      await session.api.deleteInvite(store.tripId, pendingRemove.id);
      setInvites((current) => current.filter((item) => item.id !== pendingRemove.id));
      setPendingRemove(null);
      toast("Invite withdrawn", "success");
    } catch (caught) {
      toast(caught instanceof Error ? caught.message : "Couldn't withdraw the invite.", "error");
    } finally {
      setRemoving(false);
    }
  }

  if (!session.isSignedIn || store.isGuest) {
    return (
      <div className="tool-page share-page">
        <header className="tool-heading">
          <div>
            <p className="context-line">Bring people in</p>
            <h1>Share this trip</h1>
            <p>A public link, email invites, and one shared page for the group.</p>
          </div>
        </header>
        <div className="share-guest-card">
          <span className="share-guest-card__icon"><Users size={28} /></span>
          <p className="context-line">Guest plan</p>
          <h2>Sign in to invite the group</h2>
          <p>Your guest trip is safe on this device. Create a free account to copy it in, invite people, and use your private layer.</p>
          <div className="share-guest-card__actions">
            <button type="button" className="button button--primary" onClick={session.signIn}>Sign in or create an account</button>
            <button type="button" className="button button--secondary" onClick={() => window.print()}>Print the itinerary</button>
          </div>
          <p className="quiet-note">You can still print or export this guest trip from the Notes tab.</p>
        </div>
      </div>
    );
  }

  const pending = invites.filter((invite) => !invite.accepted_at);
  const memberEmails = new Set(members.map((member) => member.email?.toLowerCase()).filter(Boolean));
  const visibleInvites = pending.filter((invite) => !memberEmails.has(invite.email.toLowerCase()));

  return (
    <div className="tool-page share-page">
      <header className="tool-heading">
        <div>
          <p className="context-line">Bring people in</p>
          <h1>Share this trip</h1>
          <p>The public link is read-only. Invited people can edit or just follow along.</p>
        </div>
      </header>

      <div className="share-layout">
        <div className="share-main">
          <section className="share-link-card" aria-labelledby="share-link-heading">
            <div className="share-link-card__head">
              <span className="share-link-card__icon"><Link2 size={18} /></span>
              <div>
                <h2 id="share-link-heading">Public link</h2>
                <p>Anyone with this link can see the itinerary. They can't edit it.</p>
              </div>
            </div>
            {publicLink ? (
              <>
                <div className="copy-field">
                  <input readOnly value={publicLink} aria-label="Public trip link" onFocus={(event) => event.currentTarget.select()} />
                  <button type="button" className="button button--ink button--small" onClick={() => void copy(publicLink)}>
                    {copied ? <Check size={15} /> : <Copy size={15} />} {copied ? "Copied" : "Copy"}
                  </button>
                </div>
                <div className="share-link-card__actions">
                  <a href={publicLink} target="_blank" rel="noreferrer" className="text-link"><ExternalLink size={14} /> Preview the public page</a>
                  {owner && (
                    <button type="button" className="text-link danger-link" onClick={() => setRegenerateOpen(true)}>
                      <RefreshCw size={14} /> Make a new link
                    </button>
                  )}
                </div>
                <p className="quiet-note">
                  {owner
                    ? "Making a new link turns the current one off for everyone who has it."
                    : "Only the trip owner can replace the public link."}
                </p>
              </>
            ) : (
              <p className="quiet-note">A public link hasn't been created for this trip yet.</p>
            )}
          </section>

          <section className="invite-card" aria-labelledby="invite-heading">
            <div className="section-heading section-heading--compact">
              <div>
                <h2 id="invite-heading">Invite someone</h2>
                <p className="quiet-note">They'll get an email. If it's their first visit, the trip appears after they sign in.</p>
              </div>
            </div>
            <form className="invite-form" onSubmit={invite}>
              <label className="field">
                <span className="field__label"><Mail size={14} /> Email address</span>
                <input
                  type="email"
                  value={email}
                  onChange={(event) => setEmail(event.target.value)}
                  placeholder="friend@example.com"
                  disabled={!canInvite}
                  required
                />
              </label>
              <label className="field">
                <span className="field__label">They can</span>
                <select value={role} onChange={(event) => setRole(event.target.value as "editor" | "viewer")} disabled={!canInvite}>
                  <option value="editor">Edit the trip</option>
                  <option value="viewer">View only</option>
                </select>
              </label>
              <button type="submit" className="button button--primary" disabled={!canInvite || inviting}>
                <Send size={16} /> {inviting ? "Inviting…" : "Send invite"}
              </button>
            </form>
            {inviteError && <p className="form-error" role="alert">{inviteError}</p>}
            {!canInvite && <p className="quiet-note">View-only access means you can't send new invites.</p>}
          </section>

          {visibleInvites.length > 0 && (
            <section className="pending-card" aria-labelledby="pending-heading">
              <div className="section-heading section-heading--compact">
                <div>
                  <h2 id="pending-heading">Invites waiting</h2>
                  <p className="quiet-note">{visibleInvites.length} sent but not accepted yet.</p>
                </div>
              </div>
              <div className="pending-list">
                {visibleInvites.map((invite) => {
                  const inviteLink = invite.token ? `${API_URL}/invite/${invite.token}` : null;
                  return (
                    <div className="pending-row" key={invite.id}>
                      <span className="pending-row__avatar"><Mail size={15} /></span>
                      <span className="pending-row__copy">
                        <strong>{invite.email}</strong>
                        <small>{invite.role === "viewer" ? "Can view" : "Can edit"} · Expires {invite.expires_at ? fmtDate(invite.expires_at.slice(0, 10)) : "later"}</small>
                      </span>
                      {inviteLink && (
                        <button type="button" className="text-link" onClick={() => void copy(inviteLink, "Invite link copied")}>
                          Copy invite link
                        </button>
                      )}
                      <button type="button" className="icon-button icon-button--quiet is-danger" onClick={() => setPendingRemove(invite)} aria-label={`Withdraw invite for ${invite.email}`} title="Withdraw invite">
                        <Trash2 size={15} />
                      </button>
                    </div>
                  );
                })}
              </div>
            </section>
          )}
          {invitesError && <p className="inline-error">{invitesError}</p>}
        </div>

        <aside className="members-card" aria-labelledby="members-heading">
          <div className="section-heading section-heading--compact">
            <div>
              <h2 id="members-heading">On this trip</h2>
              <p className="quiet-note">{members.length} {members.length === 1 ? "person" : "people"}</p>
            </div>
            <UserPlus size={17} />
          </div>
          <div className="member-list">
            {members.map((member) => (
              <MemberRow key={member.user_id} member={member} isYou={member.user_id === store.currentUserId} />
            ))}
          </div>
          <div className="members-card__note">
            <Users size={16} />
            <p>Everyone's changes are shared. Anything in your private layer stays yours alone.</p>
          </div>
        </aside>
      </div>

      <ConfirmDialog
        open={regenerateOpen}
        onClose={() => setRegenerateOpen(false)}
        onConfirm={regenerate}
        title="Make a new public link?"
        message="The current link will stop working for everyone who has it. Anyone you invite by email stays on the trip."
        confirmLabel="Make a new link"
        destructive
        busy={regenerating}
      />
      <ConfirmDialog
        open={Boolean(pendingRemove)}
        onClose={() => setPendingRemove(null)}
        onConfirm={removeInvite}
        title="Withdraw this invite?"
        message={pendingRemove ? `${pendingRemove.email} won't be able to use their invite link.` : ""}
        confirmLabel="Withdraw invite"
        destructive
        busy={removing}
      />
    </div>
  );
}

function MemberRow({ member, isYou }: { member: Member; isYou: boolean }) {
  const name = isYou ? "You" : summaryName(member.display_name, member.email);
  return (
    <div className="member-row">
      <Avatar name={summaryName(member.display_name, member.email)} size="sm" />
      <span className="member-row__copy">
        <strong>{name}</strong>
        <small>{member.email || "No email on profile"}</small>
      </span>
      <span className={`member-role member-role--${member.role}`}>
        {member.role === "owner" ? "Owner" : member.role === "viewer" ? "View only" : "Editor"}
      </span>
    </div>
  );
}
