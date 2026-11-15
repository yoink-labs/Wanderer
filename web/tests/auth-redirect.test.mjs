import assert from "node:assert/strict";
import { test } from "node:test";
import { authReturnPath, signInHref } from "../src/auth/redirect.ts";

test("sign-in returns to a guest trip or shared link with its query and fragment", () => {
  const path = "/trips/kyoto?invite=travel%20friends#day-2";
  const href = new URL(signInHref(path), "https://wanderer.yoinklabs.dev");
  assert.equal(href.pathname, "/sign-in");
  assert.equal(authReturnPath(href.searchParams.get("redirect_url")), path);
});

test("unsafe or external redirects fall back to trips", () => {
  for (const path of [null, "", "https://example.com", "//example.com", "/\\example.com", "javascript:alert(1)"]) {
    assert.equal(authReturnPath(path), "/", String(path));
  }
});

test("auth routes cannot send a signed-in user back into sign-in or sign-up", () => {
  for (const path of ["/sign-in", "/sign-up?redirect_url=/", "/sign-in/factor-one", "/sign-up/verify-email-address"]) {
    assert.equal(authReturnPath(path), "/");
  }
});
