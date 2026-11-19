// The parts: connection ids, SSE, reading a client's messages, the memory host, the handler's edges, and that the
// embedded fixtures are protocol/fixtures as they stand.
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { localRooms } from "../../src/conformance.ts";
import { fixtures } from "../../src/fixtures.generated.ts";
import { CONNECTION_HEADER, handleAcp, SESSION_HEADER } from "../../src/handler.ts";
import { MemorySessions } from "../../src/memory.ts";

test("the handler: DELETE ends a connection, other methods are 405, initialize needs an id", async () => {
  const sessions = new MemorySessions();
  sessions.create("s", "jai");
  const adapter = sessions.adapter();
  const rooms = localRooms(adapter);
  const route = { adapter, rooms, secret: "x" };
  const json = { "Content-Type": "application/json" };
  const init = await handleAcp(
    new Request("https://h/acp", {
      method: "POST",
      headers: json,
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "initialize", params: {} }),
    }),
    route,
  );
  const connection = init.headers.get(CONNECTION_HEADER) ?? "";
  assert.equal(init.status, 200);
  const headers = {
    Authorization: "Bearer token-jai",
    Accept: "text/event-stream",
    [CONNECTION_HEADER]: connection,
    [SESSION_HEADER]: "s",
  };
  const stream = await handleAcp(new Request("https://h/acp", { headers }), route);
  assert.equal(stream.status, 200);
  assert.equal(rooms.room("s").streams, 1);
  const gone = await handleAcp(new Request("https://h/acp", { method: "DELETE", headers }), route);
  assert.equal(gone.status, 202);
  assert.equal(rooms.room("s").streams, 0);
  await stream.body?.cancel();
  assert.equal((await handleAcp(new Request("https://h/acp", { method: "DELETE" }), route)).status, 400);
  assert.equal((await handleAcp(new Request("https://h/acp", { method: "PUT" }), route)).status, 405);
  const noId = await handleAcp(
    new Request("https://h/acp", {
      method: "POST",
      headers: json,
      body: JSON.stringify({ jsonrpc: "2.0", method: "initialize", params: {} }),
    }),
    route,
  );
  assert.equal(noId.status, 400);
  const noSessionStream = await handleAcp(
    new Request("https://h/acp", { headers: { Accept: "text/event-stream", [CONNECTION_HEADER]: connection } }),
    route,
  );
  assert.equal(noSessionStream.status, 400);
});

test("the embedded fixtures are protocol/fixtures as they stand (npm run fixtures)", () => {
  const source = join(import.meta.dirname, "..", "..", "..", "protocol", "fixtures");
  const files = readdirSync(source).filter((name) => name.endsWith(".json"));
  assert.deepEqual(Object.keys(fixtures).sort(), files.map((name) => name.replace(/\.json$/, "")).sort());
  for (const name of files) {
    assert.deepEqual(fixtures[name.replace(/\.json$/, "")], JSON.parse(readFileSync(join(source, name), "utf8")), name);
  }
});
