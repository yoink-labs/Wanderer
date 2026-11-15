const LOCAL_ORIGIN = "https://wanderer.invalid";
const AUTH_PATH = /^\/sign-(?:in|up)(?:\/|$)/;

/** Keep auth returns inside Wanderer, including guest trips and shared links. */
export function authReturnPath(value: string | null): string {
  if (!value?.startsWith("/")) return "/";
  try {
    const url = new URL(value, LOCAL_ORIGIN);
    if (url.origin !== LOCAL_ORIGIN || AUTH_PATH.test(url.pathname)) return "/";
    return url.pathname + url.search + url.hash;
  } catch {
    return "/";
  }
}

export function signInHref(returnTo: string): string {
  return `/sign-in?redirect_url=${encodeURIComponent(authReturnPath(returnTo))}`;
}
