const LOCAL_ORIGIN = "https://wanderer.invalid";
const AUTH_PATH = /^\/sign-(?:in|up)(?:\/|$)/;

/** Keep auth returns inside Wanderer, including guest trips and shared links. */
export function authReturnPath(value: string | null, origin = LOCAL_ORIGIN): string {
  // Clerk normalizes redirect_url to an absolute URL when switching flows.
  if (!value || (!value.startsWith("/") && !/^https?:\/\//i.test(value))) return "/";
  try {
    const url = new URL(value, origin);
    if (url.origin !== origin || AUTH_PATH.test(url.pathname)) return "/";
    return url.pathname + url.search + url.hash;
  } catch {
    return "/";
  }
}

export function signInHref(returnTo: string): string {
  return `/sign-in?redirect_url=${encodeURIComponent(authReturnPath(returnTo))}`;
}
