import {
  SignIn as ClerkSignIn,
  SignUp as ClerkSignUp,
  ClerkLoaded,
  ClerkLoading,
} from "@clerk/clerk-react";
import { ArrowLeft, Compass } from "lucide-react";
import { Link, Navigate, useSearchParams } from "react-router-dom";
import { authReturnPath } from "../auth/redirect";
import { useSession } from "../auth/session";
import { Logo } from "../components/Logo";

export default function SignIn({ signUp = false }: { signUp?: boolean }) {
  const session = useSession();
  const [searchParams] = useSearchParams();
  const returnTo = authReturnPath(searchParams.get("redirect_url"), window.location.origin);
  const returnQuery = `?redirect_url=${encodeURIComponent(returnTo)}`;
  if (session.isSignedIn) return <Navigate to={returnTo} replace />;
  return (
    <div className="signin-page">
      <div className="signin-story">
        <img
          src="/images/kyoto.jpg"
          alt="A quiet street and traditional architecture in Kyoto"
        />
        <div>
          <span className="journey-eyebrow">EVERY JOURNEY HAS A BEGINNING</span>
          <h2>
            A world of plans.
            <br />
            One place to return.
          </h2>
          <p>Pick up where you left off, wherever you are.</p>
        </div>
        <span className="signin-story__location">
          <Compass size={16} /> Kyoto, Japan
        </span>
      </div>
      <section className="signin-welcome">
        <Logo />
        <p className="journey-kicker">{signUp ? "MAKE ROOM FOR A LITTLE WANDER" : "WELCOME BACK, WANDERER"}</p>
        <div className="signin-form">
          <ClerkLoading>
            <p className="signin-loading" role="status">Getting your journey ready…</p>
          </ClerkLoading>
          <ClerkLoaded>
            {signUp ? (
              <ClerkSignUp
                routing="path"
                path="/sign-up"
                signInUrl={`/sign-in${returnQuery}`}
                forceRedirectUrl={returnTo}
                signInForceRedirectUrl={returnTo}
              />
            ) : (
              <ClerkSignIn
                routing="path"
                path="/sign-in"
                signUpUrl={`/sign-up${returnQuery}`}
                forceRedirectUrl={returnTo}
                signUpForceRedirectUrl={returnTo}
              />
            )}
          </ClerkLoaded>
        </div>
        <div className="signin-divider">
          <span>Just looking around?</span>
        </div>
        <Link to="/" className="text-link">
          <ArrowLeft size={15} /> Keep exploring as a guest
        </Link>
        <small>One Yoink Labs account. All your Wanderer trips.</small>
      </section>
    </div>
  );
}
