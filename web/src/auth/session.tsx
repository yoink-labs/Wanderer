import { ClerkProvider, useAuth, useClerk, useUser } from "@clerk/clerk-react";
import { createContext, useCallback, useContext, useMemo, type ReactNode } from "react";
import { TEST_TOKEN, USE_TEST_AUTH, WandererApi } from "../lib/api";

export interface SessionUser {
  id: string | null;
  displayName: string;
  email: string | null;
  avatarUrl: string | null;
}

export interface SessionValue {
  mode: "test" | "clerk";
  isLoaded: boolean;
  isSignedIn: boolean;
  isTest: boolean;
  user: SessionUser | null;
  api: WandererApi;
  signIn: () => void;
  signOut: () => Promise<void>;
  openProfile: () => void;
}

const SessionContext = createContext<SessionValue | null>(null);

export function useSession(): SessionValue {
  const value = useContext(SessionContext);
  if (!value) throw new Error("useSession must be used inside SessionHost");
  return value;
}

const TEST_EMAIL = TEST_TOKEN.includes("|") ? TEST_TOKEN.split("|")[1] : "web@example.com";
const TEST_SUB = TEST_TOKEN.replace(/^test:/, "").split("|")[0] || "webuser";
const TEST_LOCAL = TEST_EMAIL.split("@")[0] || TEST_SUB;
const TEST_NAME = TEST_LOCAL.charAt(0).toUpperCase() + TEST_LOCAL.slice(1);

function TestSessionHost({ children }: { children: ReactNode }) {
  const api = useMemo(() => new WandererApi(async () => TEST_TOKEN), []);
  const value = useMemo<SessionValue>(
    () => ({
      mode: "test",
      isLoaded: true,
      isSignedIn: true,
      isTest: true,
      user: {
        id: null,
        displayName: TEST_NAME,
        email: TEST_EMAIL,
        avatarUrl: null,
      },
      api,
      signIn: () => undefined,
      signOut: async () => undefined,
      openProfile: () => undefined,
    }),
    [api],
  );
  return <SessionContext.Provider value={value}>{children}</SessionContext.Provider>;
}

function ClerkSessionHost({ children }: { children: ReactNode }) {
  const { isLoaded, isSignedIn, getToken } = useAuth();
  const { user } = useUser();
  const clerk = useClerk();

  const api = useMemo(() => new WandererApi(getToken), [getToken]);

  const signOut = useCallback(async () => {
    await clerk.signOut({ redirectUrl: "/" });
  }, [clerk]);

  const value = useMemo<SessionValue>(
    () => ({
      mode: "clerk",
      isLoaded,
      isSignedIn: Boolean(isSignedIn),
      isTest: false,
      user: user
        ? {
            id: user.id,
            displayName: user.fullName || user.username || user.primaryEmailAddress?.emailAddress.split("@")[0] || "Traveler",
            email: user.primaryEmailAddress?.emailAddress ?? null,
            avatarUrl: user.imageUrl ?? null,
          }
        : null,
      api,
      signIn: () => {
        void clerk.openSignIn({});
      },
      signOut,
      openProfile: () => {
        void clerk.openUserProfile();
      },
    }),
    [api, clerk, isLoaded, isSignedIn, signOut, user],
  );

  return <SessionContext.Provider value={value}>{children}</SessionContext.Provider>;
}

const CLERK_APPEARANCE = {
  variables: {
    colorPrimary: "#F2A922",
    colorText: "#10283A",
    colorTextSecondary: "#56697A",
    colorBackground: "#FFFFFF",
    colorInputBackground: "#F3F6F5",
    colorInputText: "#10283A",
    borderRadius: "14px",
    fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Display", "Segoe UI", system-ui, sans-serif',
    fontSize: "15px",
  },
  elements: {
    card: "wanderer-clerk-card",
    formButtonPrimary: "wanderer-clerk-primary",
    footerActionLink: "wanderer-clerk-link",
  },
};

export function SessionHost({ children }: { children: ReactNode }) {
  if (USE_TEST_AUTH) return <TestSessionHost>{children}</TestSessionHost>;
  const publishableKey =
    (import.meta.env.VITE_CLERK_PUBLISHABLE_KEY as string | undefined) ??
    "pk_live_Y2xlcmsueW9pbmtsYWJzLmRldiQ";
  return (
    <ClerkProvider publishableKey={publishableKey} appearance={CLERK_APPEARANCE}>
      <ClerkSessionHost>{children}</ClerkSessionHost>
    </ClerkProvider>
  );
}
