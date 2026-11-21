import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { test } from "node:test";

const read = (path) => readFile(new URL(path, import.meta.url), "utf8");

test("the header links Tip the devs to the shared Yoink Labs tip page", async () => {
  const header = await read("../src/components/AppHeader.tsx");
  assert.match(header, /TIP_URL = "https:\/\/yoinklabs\.dev\/tip"/);
  assert.match(header, /<TipPill \/>/);
  assert.match(header, /Tip the devs/);
});

test("no web copy claims a tip can be paid on the web", async () => {
  for (const file of ["../src/components/AppHeader.tsx", "../src/pages/Landing.tsx"]) {
    const source = await read(file);
    assert.doesNotMatch(source, /tip (now|today)|supports us today|pay (a tip )?here/i, file);
  }
});
