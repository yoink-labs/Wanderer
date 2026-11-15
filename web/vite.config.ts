import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { defineConfig, type Plugin } from "vite";
import react from "@vitejs/plugin-react";

import { cloudflare } from "@cloudflare/vite-plugin";
import { PRIVACY_TITLE, privacyArticleHtml } from "./src/content/privacy";

/**
 * Writes dist/privacy.html: the built index.html with the privacy policy
 * already rendered inside #root. Cloudflare serves it at /privacy with a 200,
 * so a cold load, curl or App Review sees the policy before any JavaScript
 * runs; the app then mounts over it and renders the same page.
 */
function prerenderPrivacy(): Plugin {
  const logo =
    '<span class="logo" aria-label="Wanderer"><svg class="logo__mark" viewBox="0 0 42 32" aria-hidden="true">' +
    '<path d="M3 23.5c6.8-15 12.8-15.5 19.1-4.2 4.4 8 8.2 4.5 10.1-2.5" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"></path>' +
    '<circle cx="33.5" cy="15" r="3.4" fill="var(--route)"></circle></svg><span class="logo__word">Wanderer</span></span>';
  const header =
    '<header class="site-header"><div class="site-header__inner">' +
    `<a href="/" class="site-header__brand" aria-label="Wanderer home">${logo}</a>` +
    '<nav class="site-nav" aria-label="Primary"><a class="site-nav__link" href="/">Trips</a><a class="site-nav__link" href="/guides">Guides</a></nav>' +
    "</div></header>";
  return {
    name: "wanderer:prerender-privacy",
    apply: "build",
    async writeBundle(options, bundle) {
      if (!options.dir || !("index.html" in bundle)) return;
      const shell = await readFile(join(options.dir, "index.html"), "utf8");
      const body = `${header}<main id="main-content">${privacyArticleHtml()}</main>`;
      const html = shell
        .replace(/<title>[^<]*<\/title>/, `<title>${PRIVACY_TITLE} · Wanderer</title>`)
        .replace(
          /<meta name="description" content="[^"]*" \/>/,
          '<meta name="description" content="How Wanderer collects, stores and deletes your data." />',
        )
        .replace('<div id="root"></div>', `<div id="root">${body}</div>`);
      if (!html.includes("legal-page")) {
        throw new Error("prerender-privacy: could not inject the policy into index.html");
      }
      await writeFile(join(options.dir, "privacy.html"), html);
    },
  };
}

export default defineConfig({
  plugins: [react(), cloudflare(), prerenderPrivacy()],
  server: { port: 5173 },
});
