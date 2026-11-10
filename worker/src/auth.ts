/**
 * Clerk session JWT verification.
 *
 * The Worker verifies Clerk's RS256 session token itself against the instance
 * JWKS, so no Clerk server SDK and no shared secret is needed. This must only
 * accept tokens issued by the configured Clerk instance: signature, issuer and
 * authorized party are all checked.
 */

export interface AuthConfig {
  jwksUrl: string;
  issuer: string;
  authorizedParties: string[];
}

export interface ClerkClaims {
  sub: string;
  email?: string;
  name?: string;
  [key: string]: unknown;
}

export class AuthError extends Error {
  readonly status = 401;
  readonly code: string;

  constructor(code: string, message: string) {
    super(message);
    this.code = code;
  }
}

const LEewaySeconds = 60;
const JWKS_TTL_MS = 5 * 60 * 1000;

let cachedJwks: { url: string; fetchedAt: number; keys: JsonWebKey[] } | null = null;

function base64UrlToBytes(value: string): Uint8Array {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized.padEnd(normalized.length + ((4 - (normalized.length % 4)) % 4), "=");
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

function decodeJsonSegment<T>(segment: string): T {
  const text = new TextDecoder().decode(base64UrlToBytes(segment));
  return JSON.parse(text) as T;
}

export async function fetchJwks(url: string, fetchImpl: typeof fetch = fetch): Promise<JsonWebKey[]> {
  const now = Date.now();
  if (cachedJwks && cachedJwks.url === url && now - cachedJwks.fetchedAt < JWKS_TTL_MS) {
    return cachedJwks.keys;
  }
  const response = await fetchImpl(url, { headers: { accept: "application/json" } }).catch(() => null);
  if (!response || !response.ok) {
    throw new AuthError("jwks_unavailable", "Could not load the signing keys.");
  }
  const body = (await response.json()) as { keys?: JsonWebKey[] };
  const keys = Array.isArray(body.keys) ? body.keys : [];
  if (keys.length === 0) {
    throw new AuthError("jwks_empty", "The signing key set is empty.");
  }
  cachedJwks = { url, fetchedAt: now, keys };
  return keys;
}

export async function verifyClerkJwt(
  token: string,
  config: AuthConfig,
  fetchImpl: typeof fetch = fetch,
): Promise<ClerkClaims> {
  const parts = token.split(".");
  if (parts.length !== 3) {
    throw new AuthError("malformed_token", "The session token is malformed.");
  }
  const [encodedHeader, encodedPayload, encodedSignature] = parts;

  let header: { alg?: string; kid?: string; typ?: string };
  try {
    header = decodeJsonSegment(encodedHeader);
  } catch {
    throw new AuthError("malformed_token", "The session token header is not valid JSON.");
  }
  if (header.alg !== "RS256") {
    throw new AuthError("unsupported_algorithm", "Unsupported session token algorithm.");
  }
  if (!header.kid) {
    throw new AuthError("missing_key_id", "The session token has no key id.");
  }

  const keys = await fetchJwks(config.jwksUrl, fetchImpl);
  const jwk = keys.find((key) => (key as JsonWebKey & { kid?: string }).kid === header.kid);
  if (!jwk) {
    // A rotation may have happened since the cache was filled.
    cachedJwks = null;
    const refreshed = await fetchJwks(config.jwksUrl, fetchImpl);
    const retry = refreshed.find((key) => (key as JsonWebKey & { kid?: string }).kid === header.kid);
    if (!retry) {
      throw new AuthError("unknown_key", "The session token was signed by an unknown key.");
    }
    return verifyWithKey(retry, { encodedHeader, encodedPayload, encodedSignature }, config);
  }

  return verifyWithKey(jwk, { encodedHeader, encodedPayload, encodedSignature }, config);
}

async function verifyWithKey(
  jwk: JsonWebKey,
  parts: { encodedHeader: string; encodedPayload: string; encodedSignature: string },
  config: AuthConfig,
): Promise<ClerkClaims> {
  const key = await crypto.subtle.importKey(
    "jwk",
    { kty: jwk.kty, n: jwk.n, e: jwk.e, alg: "RS256", ext: true },
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["verify"],
  );

  const valid = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    key,
    base64UrlToBytes(parts.encodedSignature),
    new TextEncoder().encode(`${parts.encodedHeader}.${parts.encodedPayload}`),
  );
  if (!valid) {
    throw new AuthError("bad_signature", "The session token signature is invalid.");
  }

  let claims: ClerkClaims;
  try {
    claims = decodeJsonSegment<ClerkClaims>(parts.encodedPayload);
  } catch {
    throw new AuthError("malformed_token", "The session token payload is not valid JSON.");
  }

  const now = Math.floor(Date.now() / 1000);
  if (typeof claims.exp === "number" && now > claims.exp + LEewaySeconds) {
    throw new AuthError("expired_token", "The session has expired.");
  }
  if (typeof claims.nbf === "number" && now + LEewaySeconds < claims.nbf) {
    throw new AuthError("token_not_yet_valid", "The session is not valid yet.");
  }
  if (typeof claims.sub !== "string" || claims.sub.length === 0) {
    throw new AuthError("missing_subject", "The session token has no subject.");
  }
  if (config.issuer && claims.iss !== config.issuer) {
    throw new AuthError("wrong_issuer", "The session token came from another issuer.");
  }
  const parties = config.authorizedParties.filter((value) => value.length > 0);
  if (parties.length > 0) {
    const azp = typeof claims.azp === "string" ? claims.azp : "";
    if (!parties.includes(azp)) {
      throw new AuthError("untrusted_party", "The session token was issued to an untrusted client.");
    }
  }

  return claims;
}
