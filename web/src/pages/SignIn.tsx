import { ArrowLeft, ArrowRight, Compass, ShieldCheck } from "lucide-react";
import { Link, Navigate } from "react-router-dom";
import { useSession } from "../auth/session";
import { Logo } from "../components/Logo";

export default function SignIn() {
  const session = useSession();
  if (session.isSignedIn) return <Navigate to="/" replace />;
  return (
    <div className="signin-page">
      <div className="signin-story">
        <img
          src="/images/kyoto.jpg"
          alt="A quiet street and traditional architecture in Kyoto"
        />
        <div>
          <span className="journey-eyebrow">EVERY JOURNEY HAS A BEGINNING</span>
          <h1>
            A world of plans.
            <br />
            One place to return.
          </h1>
          <p>Pick up where you left off, wherever you are.</p>
        </div>
        <span className="signin-story__location">
          <Compass size={16} /> Kyoto, Japan
        </span>
      </div>
      <section className="signin-welcome">
        <Logo />
        <p className="journey-kicker">WELCOME BACK, WANDERER</p>
        <h2>
          Your next chapter
          <br />
          starts here.
        </h2>
        <p>
          Sign in with your Yoink Labs account to keep your trips in sync and
          bring your people along.
        </p>
        <button
          type="button"
          className="button button--primary button--large"
          onClick={session.signIn}
          disabled={!session.isLoaded}
        >
          Continue to sign in <ArrowRight size={18} />
        </button>
        <span className="signin-trust">
          <ShieldCheck size={15} /> Secure sign-in with Clerk
        </span>
        <div className="signin-divider">
          <span>Just looking around?</span>
        </div>
        <Link to="/" className="text-link">
          <ArrowLeft size={15} /> Keep exploring as a guest
        </Link>
        <small>Free to use. Open source. No paywall.</small>
      </section>
    </div>
  );
}
