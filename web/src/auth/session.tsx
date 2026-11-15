import { ClerkProvider, useAuth, useClerk, useUser } from "@clerk/clerk-react";
import {
  createContext,
  useCallback,
  useContext,
  useMemo,
  type ReactNode,
} from "react";
import { signInHref } from "./redirect";
import { useNavigate } from "react-router-dom";
import { useTheme } from "../lib/theme";
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

const TEST_EMAIL = TEST_TOKEN.includes("|")
  ? TEST_TOKEN.split("|")[1]
  : "web@example.com";
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
  return (
    <SessionContext.Provider value={value}>{children}</SessionContext.Provider>
  );
}

function ClerkSessionHost({ children }: { children: ReactNode }) {
  const { isLoaded, isSignedIn, getToken } = useAuth();
  const { user } = useUser();
  const clerk = useClerk();
  const navigate = useNavigate();

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
            displayName:
              user.fullName ||
              user.username ||
              user.primaryEmailAddress?.emailAddress.split("@")[0] ||
              "Traveler",
            email: user.primaryEmailAddress?.emailAddress ?? null,
            avatarUrl: user.imageUrl ?? null,
          }
        : null,
      api,
      signIn: () => {
        const returnTo = window.location.pathname + window.location.search + window.location.hash;
        navigate(signInHref(returnTo));
      },
      signOut,
      openProfile: () => {
        void clerk.openUserProfile();
      },
    }),
    [api, clerk, isLoaded, isSignedIn, navigate, signOut, user],
  );

  return (
    <SessionContext.Provider value={value}>{children}</SessionContext.Provider>
  );
}

// Keep the free-plan Clerk attribution visible. These stable element classes
// also apply to verification, recovery and sign-up steps.
const CLERK_ELEMENTS = {
  rootBox: "wanderer-clerk-root",
  cardBox: "wanderer-clerk-box",
  card: "wanderer-clerk-card",
  header: "wanderer-clerk-header",
  headerTitle: "wanderer-clerk-title",
  headerSubtitle: "wanderer-clerk-subtitle",
  socialButtons: "wanderer-clerk-providers",
  socialButtonsBlockButton: "wanderer-clerk-social",
  formFieldInput: "wanderer-clerk-input",
  formButtonPrimary: "wanderer-clerk-primary",
  footer: "wanderer-clerk-footer",
  footerActionLink: "wanderer-clerk-link",
};

export function SessionHost({ children }: { children: ReactNode }) {
  const { resolved } = useTheme();
  const dark = resolved === "dark";
  if (USE_TEST_AUTH) return <TestSessionHost>{children}</TestSessionHost>;
  const publishableKey =
    (import.meta.env.VITE_CLERK_PUBLISHABLE_KEY as string | undefined) ??
    "pk_live_Y2xlcmsueW9pbmtsYWJzLmRldiQ";
  return (
    <ClerkProvider
      publishableKey={publishableKey}
      signInUrl="/sign-in"
      signUpUrl="/sign-up"
      signInFallbackRedirectUrl="/"
      signUpFallbackRedirectUrl="/"
      localization={{
        signIn: {
          start: {
            title: "Sign in to Wanderer",
            titleCombined: "Sign in to Wanderer",
            subtitle: "Your next chapter starts here.",
            subtitleCombined: "Your next chapter starts here.",
          },
        },
        signUp: {
          start: {
            title: "Join Wanderer",
            subtitle: "A world of plans. One place for yours.",
          },
        },
      }}
      appearance={{
        elements: CLERK_ELEMENTS,
        layout: { socialButtonsVariant: "blockButton", socialButtonsPlacement: "top" },
        variables: {
          colorPrimary: dark ? "#FFC14D" : "#10283A",
          colorText: dark ? "#E8EEF1" : "#10283A",
          colorTextSecondary: dark ? "#93A6B3" : "#56697A",
          colorBackground: dark ? "#101B23" : "#FFFFFF",
          colorInputBackground: dark ? "#16242E" : "#EEF2F3",
          colorInputText: dark ? "#E8EEF1" : "#10283A",
          colorTextOnPrimaryBackground: dark ? "#10283A" : "#FFFFFF",
          colorNeutral: dark ? "#E8EEF1" : "#10283A",
          fontFamily:
            'Inter, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
          colorDanger: dark ? "#FF8A78" : "#C8402F",
          borderRadius: "12px",
          fontSize: "15px",
        },
      }}
    >
      <ClerkSessionHost>{children}</ClerkSessionHost>
    </ClerkProvider>
  );
}
