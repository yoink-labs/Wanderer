import { describe, expect, it } from "vitest";
import { verifyClerkJwt, AuthError } from "../src/auth";
import { authenticate } from "../src/index";
import { env } from "cloudflare:test";

const issuer = "https://clerk.test";
const party = "wanderer://callback";

function base64url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function encodeJson(value: unknown): string {
  return base64url(new TextEncoder().encode(JSON.stringify(value)));
}

async function keyPair(kid: string) {
  const pair = (await crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign", "verify"],
  )) as CryptoKeyPair;
  const jwk = (await crypto.subtle.exportKey("jwk", pair.publicKey)) as JsonWebKey;
  return { pair, kid, publicJwk: { ...jwk, kid, alg: "RS256", use: "sig" } };
}

async function signToken(
  claims: Record<string, unknown>,
  pair: CryptoKeyPair,
  kid: string,
  header: Record<string, unknown> = { alg: "RS256", typ: "JWT", kid },
): Promise<string> {
  const head = encodeJson(header);
  const payload = encodeJson(claims);
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    pair.privateKey,
    new TextEncoder().encode(`${head}.${payload}`),
  );
  return `${head}.${payload}.${base64url(new Uint8Array(signature))}`;
}

function jwksFetch(keys: JsonWebKey[]): typeof fetch {
  return (async () =>
    new Response(JSON.stringify({ keys }), { headers: { "content-type": "application/json" } })) as typeof fetch;
}

const config = { jwksUrl: `${issuer}/.well-known/jwks.json`, issuer, authorizedParties: [party] };

describe("Clerk session token verification", () => {
  it("accepts a correctly signed token", async () => {
    const { pair, publicJwk, kid } = await keyPair(`kid_${crypto.randomUUID()}`);
    const now = Math.floor(Date.now() / 1000);
    const jwt = await signToken(
      { sub: "user_123", iss: issuer, azp: party, exp: now + 600, iat: now },
      pair,
      kid,
    );
    const claims = await verifyClerkJwt(jwt, config, jwksFetch([publicJwk]));
    expect(claims.sub).toBe("user_123");
  });

  it("rejects a tampered payload", async () => {
    const { pair, publicJwk, kid } = await keyPair(`kid_${crypto.randomUUID()}`);
    const now = Math.floor(Date.now() / 1000);
    const jwt = await signToken(
      { sub: "user_123", iss: issuer, azp: party, exp: now + 600 },
      pair,
      kid,
    );
    const [head, payload, signature] = jwt.split(".");
    const forged = encodeJson({ sub: "user_admin", iss: issuer, azp: party, exp: now + 600 });
    await expect(
      verifyClerkJwt(`${head}.${forged}.${signature}`, config, jwksFetch([publicJwk])),
    ).rejects.toMatchObject({ code: "bad_signature" });
  });

  it("rejects an expired token", async () => {
    const { pair, publicJwk, kid } = await keyPair(`kid_${crypto.randomUUID()}`);
    const past = Math.floor(Date.now() / 1000) - 3600;
    const jwt = await signToken({ sub: "user_1", iss: issuer, azp: party, exp: past }, pair, kid);
    await expect(verifyClerkJwt(jwt, config, jwksFetch([publicJwk]))).rejects.toMatchObject({
      code: "expired_token",
    });
  });

  it("rejects another issuer", async () => {
    const { pair, publicJwk, kid } = await keyPair(`kid_${crypto.randomUUID()}`);
    const now = Math.floor(Date.now() / 1000);
    const jwt = await signToken(
      { sub: "user_1", iss: "https://evil.test", azp: party, exp: now + 600 },
      pair,
      kid,
    );
    await expect(verifyClerkJwt(jwt, config, jwksFetch([publicJwk]))).rejects.toMatchObject({
      code: "wrong_issuer",
    });
  });

  it("rejects an untrusted client party", async () => {
    const { pair, publicJwk, kid } = await keyPair(`kid_${crypto.randomUUID()}`);
    const now = Math.floor(Date.now() / 1000);
    const jwt = await signToken(
      { sub: "user_1", iss: issuer, azp: "https://someone-else.test", exp: now + 600 },
      pair,
      kid,
    );
    await expect(verifyClerkJwt(jwt, config, jwksFetch([publicJwk]))).rejects.toMatchObject({
      code: "untrusted_party",
    });
  });

  it("rejects unsigned tokens", async () => {
    const now = Math.floor(Date.now() / 1000);
    const head = encodeJson({ alg: "none", typ: "JWT" });
    const payload = encodeJson({ sub: "user_1", iss: issuer, azp: party, exp: now + 600 });
    await expect(
      verifyClerkJwt(`${head}.${payload}.`, config, jwksFetch([])),
    ).rejects.toMatchObject({ code: "unsupported_algorithm" });
  });

  it("rejects unknown signing keys", async () => {
    const { pair } = await keyPair(`kid_${crypto.randomUUID()}`);
    const other = await keyPair(`kid_${crypto.randomUUID()}`);
    const now = Math.floor(Date.now() / 1000);
    const jwt = await signToken({ sub: "user_1", iss: issuer, azp: party, exp: now + 600 }, pair, "kid_unknown");
    await expect(
      verifyClerkJwt(jwt, config, jwksFetch([other.publicJwk])),
    ).rejects.toMatchObject({ code: "unknown_key" });
  });
});

describe("test authentication escape hatch", () => {
  it("is ignored outside the test environment", async () => {
    const request = new Request("https://api.test/v1/me", {
      headers: { authorization: "Bearer test:user_123" },
    });
    const productionLike = { ...env, ENVIRONMENT: "production", ALLOW_TEST_AUTH: "true" } as any;
    await expect(authenticate(request, productionLike)).rejects.toBeInstanceOf(AuthError);
  });

  it("is ignored when the flag is absent", async () => {
    const request = new Request("https://api.test/v1/me", {
      headers: { authorization: "Bearer test:user_123" },
    });
    const noFlag = { ...env, ENVIRONMENT: "test", ALLOW_TEST_AUTH: "" } as any;
    await expect(authenticate(request, noFlag)).rejects.toBeInstanceOf(AuthError);
  });
});
