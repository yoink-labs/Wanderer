import worker from "../src/index";
import { env } from "cloudflare:test";

export const BASE = "https://api.test";

export function token(sub: string): string {
  return `test:${sub}`;
}

interface CallOptions {
  token?: string | null;
  body?: unknown;
  headers?: Record<string, string>;
  rawBody?: BodyInit;
}

export async function call(
  method: string,
  path: string,
  options: CallOptions = {},
): Promise<Response> {
  const headers = new Headers(options.headers ?? {});
  if (options.token !== null) {
    headers.set("authorization", `Bearer ${options.token ?? token("user_a")}`);
  }
  let body: BodyInit | undefined = options.rawBody;
  if (options.body !== undefined) {
    headers.set("content-type", "application/json");
    body = JSON.stringify(options.body);
  }
  const request = new Request(`${BASE}${path}`, { method, headers, body });
  return worker.fetch(request, env as unknown as Parameters<typeof worker.fetch>[1]);
}

export async function json<T = any>(response: Response): Promise<T> {
  return (await response.json()) as T;
}

export async function createTrip(owner: string): Promise<{ id: string; [key: string]: any }> {
  const response = await call("POST", "/v1/trips", {
    token: token(owner),
    body: {
      title: "Lisbon in November",
      destination: "Lisbon, Portugal",
      start_date: "2026-11-12",
      end_date: "2026-11-16",
      timezone: "Europe/Lisbon",
    },
  });
  if (response.status !== 201) {
    throw new Error(`createTrip failed: ${response.status} ${await response.text()}`);
  }
  return json(response);
}

export async function addMember(tripId: string, userId: string, role = "editor"): Promise<void> {
  await env.DB.prepare("INSERT INTO trip_members (trip_id, user_id, role) VALUES (?, ?, ?)")
    .bind(tripId, userId, role)
    .run();
}

/** Creates a profile row and returns its id, without going through a request. */
export async function seedProfile(sub: string, email: string | null = null): Promise<string> {
  const id = crypto.randomUUID();
  await env.DB.batch([
    env.DB.prepare("INSERT INTO profiles (id, email, display_name) VALUES (?, ?, ?)").bind(id, email, sub),
    env.DB.prepare("INSERT INTO identities (clerk_sub, profile_id, email) VALUES (?, ?, ?)").bind(sub, id, email),
  ]);
  return id;
}
