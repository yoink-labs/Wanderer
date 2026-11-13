import { env, applyD1Migrations } from "cloudflare:test";
import { beforeAll } from "vitest";

declare global {
  namespace Cloudflare {
    interface Env {
    DB: D1Database;
    MEDIA: R2Bucket;
    TEST_MIGRATIONS: { name: string; queries: string[] }[];
    ENVIRONMENT: string;
    ALLOW_TEST_AUTH: string;
    MEDIA_SIGNING_SECRET: string;
    CLERK_ISSUER: string;
    CLERK_JWKS_URL: string;
      CLERK_AUTHORIZED_PARTIES: string;
    RAPIDAPI_KEY: string;
    RAPIDAPI_HOST: string;
    FLIGHT_MONTHLY_UNIT_CAP: string;
    FLIGHT_MONTHLY_REQUEST_CAP: string;
    }
  }
}

beforeAll(async () => {
  await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);
});
