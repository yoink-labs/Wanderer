import { describe, expect, it } from "vitest";
import { addMember, call, createTrip, json, seedProfile, token } from "./helpers";
import { env } from "cloudflare:test";

async function uploadAttachment(tripId: string, owner: string, name = "receipt.txt") {
  const bytes = new TextEncoder().encode("hello attachment");
  return call("POST", `/v1/trips/${tripId}/attachments`, {
    token: token(owner),
    rawBody: bytes,
    headers: {
      "content-type": "text/plain",
      "x-file-name": name,
    },
  });
}

describe("attachments and media", () => {
  it("uploads, signs and serves a file to members only", async () => {
    const trip = await createTrip("owner_files");
    const response = await uploadAttachment(trip.id, "owner_files");
    expect(response.status).toBe(201);
    const attachment = await json(response);
    expect(attachment.name).toBe("receipt.txt");
    expect(attachment.size_bytes).toBe(16);

    const signed = await json(
      await call("GET", `/v1/trips/${trip.id}/attachments/${attachment.id}/url`, {
        token: token("owner_files"),
      }),
    );
    const signedPath = new URL(signed.url).pathname + new URL(signed.url).search;
    const download = await call("GET", signedPath, { token: null });
    expect(download.status).toBe(200);
    expect(await download.text()).toBe("hello attachment");

    // The signature is bound to the exact key and expiry.
    const tampered = signedPath.replace(/sig=[0-9a-f]+/, "sig=deadbeef");
    const rejected = await call("GET", tampered, { token: null });
    expect(rejected.status).toBe(403);
  });

  it("hides attachments from non-members", async () => {
    const trip = await createTrip("owner_files_b");
    const attachment = await json(await uploadAttachment(trip.id, "owner_files_b"));

    const response = await call("GET", `/v1/trips/${trip.id}/attachments/${attachment.id}/url`, {
      token: token("files_outsider"),
    });
    expect(response.status).toBe(404);

    const list = await call("GET", `/v1/trips/${trip.id}/attachments`, {
      token: token("files_outsider"),
    });
    expect(list.status).toBe(404);
  });

  it("allows a trip member to download and delete", async () => {
    const trip = await createTrip("owner_files_c");
    const mateId = await seedProfile("files_mate");
    await addMember(trip.id, mateId);
    const attachment = await json(await uploadAttachment(trip.id, "owner_files_c"));

    const signed = await json(
      await call("GET", `/v1/trips/${trip.id}/attachments/${attachment.id}/url`, {
        token: token("files_mate"),
      }),
    );
    expect(signed.url).toContain("/media/");

    const removed = await call("DELETE", `/v1/trips/${trip.id}/attachments/${attachment.id}`, {
      token: token("files_mate"),
    });
    expect(removed.status).toBe(200);
    const objects = await env.MEDIA.list();
    expect(objects.objects.some((object) => object.key === attachment.storage_path)).toBe(false);
  });

  it("rejects oversized bodies before writing", async () => {
    const trip = await createTrip("owner_files_big");
    const response = await call("POST", `/v1/trips/${trip.id}/attachments`, {
      token: token("owner_files_big"),
      rawBody: new Uint8Array(11_000_000),
      headers: { "content-type": "application/octet-stream", "x-file-name": "big.bin" },
    });
    expect(response.status).toBe(413);
  });
});

describe("public media", () => {
  it("serves public cover objects without a signature", async () => {
    await env.MEDIA.put("public/covers/demo.jpg", new TextEncoder().encode("jpeg"), {
      httpMetadata: { contentType: "image/jpeg" },
    });
    const response = await call("GET", "/media/public/covers/demo.jpg", { token: null });
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toBe("image/jpeg");
  });

  it("never serves a private object without a signature", async () => {
    await env.MEDIA.put("trips/secret/file.pdf", new TextEncoder().encode("private"));
    const response = await call("GET", "/media/trips/secret/file.pdf", { token: null });
    expect(response.status).toBe(403);
  });
});

describe("guides", () => {
  it("lists only published guides and includes their stops", async () => {
    await env.DB.prepare(
      `INSERT INTO guides (id, title, summary, destination, is_published)
       VALUES ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Kyoto test guide', 'Shrines', 'Kyoto, Japan', 1)`,
    ).run();
    await env.DB.prepare(
      `INSERT INTO guide_places (id, guide_id, name, position)
       VALUES ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Fushimi Inari', 0)`,
    ).run();

    const list = await json(await call("GET", "/v1/guides", { token: null }));
    expect(list.some((guide: any) => guide.id === "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")).toBe(true);
    expect(list[0].is_published).toBe(true);

    const places = await json(
      await call("GET", "/v1/guides/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/places", { token: null }),
    );
    expect(places[0].name).toBe("Fushimi Inari");
  });

  it("does not expose unpublished guides", async () => {
    await env.DB.prepare(
      `INSERT INTO guides (id, title, is_published) VALUES ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'Draft', 0)`,
    ).run();
    const response = await call("GET", "/v1/guides/cccccccc-cccc-4ccc-8ccc-cccccccccccc", { token: null });
    expect(response.status).toBe(404);
  });
});
