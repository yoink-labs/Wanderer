import { defineConfig } from "vitest/config";
import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-plugin";

export default defineConfig(async () => {
  const migrations = await readD1Migrations({
    projectPath: new URL(".", import.meta.url).pathname,
  });

  return {
    plugins: [
      cloudflareTest({
        wrangler: { configPath: "./wrangler.jsonc" },
        miniflare: {
          bindings: {
            ENVIRONMENT: "test",
            ALLOW_TEST_AUTH: "true",
            MEDIA_SIGNING_SECRET: "test-secret",
            CLERK_ISSUER: "https://clerk.test",
            CLERK_JWKS_URL: "https://clerk.test/.well-known/jwks.json",
            CLERK_AUTHORIZED_PARTIES: "wanderer://callback",
            RAPIDAPI_KEY: "test-rapidapi-key",
            RAPIDAPI_HOST: "aerodatabox.p.rapidapi.com",
            FLIGHT_MONTHLY_UNIT_CAP: "380",
            FLIGHT_MONTHLY_REQUEST_CAP: "1500",
            TEST_MIGRATIONS: migrations,
          },
        },
      }),
    ],
    test: {
      setupFiles: ["./test/setup.ts"],
    },
  };
});
