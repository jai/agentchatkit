// The parts: connection ids, SSE, reading a client's messages, the memory host, the handler's edges, and that the
// embedded fixtures are protocol/fixtures as they stand.
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { readEditParams, readIncoming, readPromptParams, readResume, sessionUpdate } from "../src/acp.ts";
import { localRooms } from "../src/conformance.ts";
import { CONNECTION_LIFETIME_MS, mintConnection, verifyConnection } from "../src/connection.ts";
import { fixtures } from "../src/fixtures.generated.ts";
import { CONNECTION_HEADER, handleAcp, SESSION_HEADER } from "../src/handler.ts";
import { MemorySessions } from "../src/memory.ts";
import { encodeEvent, SSEParser } from "../src/sse.ts";

test("a connection id verifies with its secret, until it runs out", async () => {
  const id = await mintConnection("secret", 1_000);
  assert.ok(await verifyConnection("secret", id, 2_000));
  assert.ok(!(await verifyConnection("other", id, 2_000)));
  assert.ok(!(await verifyConnection("secret", id, 1_000 + CONNECTION_LIFETIME_MS)));
  assert.ok(!(await verifyConnection("secret", `${id}x`, 2_000)));
  assert.ok(!(await verifyConnection("secret", "a.b", 2_000)));
});

test("SSE: one event per message, comments apart, split anywhere", () => {
  const message = sessionUpdate("s", { sessionUpdate: "state_update", state: "idle" }, "c:1");
  const text = `${encodeEvent(message)}: keep-alive\n\n${encodeEvent({ jsonrpc: "2.0", id: 1, result: {} })}`;
  const parser = new SSEParser();
  const items = [...text].flatMap((character) => parser.push(character));
  assert.deepEqual(items, [{ message }, { comment: "keep-alive" }, { message: { jsonrpc: "2.0", id: 1, result: {} } }]);
  assert.ok(
    !encodeEvent(
      sessionUpdate(
        "s",
        { sessionUpdate: "agent_message", messageId: "m", content: [{ type: "text", text: "a\nb" }] },
        "c",
      ),
    )
      .slice(0, -2)
      .includes("\n"),
  );
});

test("reading what a client sends", () => {
  assert.equal(readIncoming([]).kind, "invalid");
  assert.equal(
    readIncoming({ jsonrpc: "2.0", method: "$/cancel_request", params: { requestId: 1 } }).kind,
    "notification",
  );
  assert.equal(readIncoming({ jsonrpc: "2.0", id: 1, result: {} }).kind, "response");
  assert.deepEqual(readResume({ sessionId: "s" }, "s"), { sessionId: "s", replayFrom: { type: "start" } });
  assert.equal(typeof readResume({ sessionId: "other" }, "s"), "string");
  assert.equal(typeof readResume({ sessionId: "s", replayFrom: { type: "_cursor" } }, "s"), "string");
  assert.equal(typeof readPromptParams({ sessionId: "s", prompt: [] }, "s"), "string");
  const five = Array.from({ length: 5 }, () => ({ type: "image", mimeType: "image/jpeg", data: "x" }));
  assert.equal(typeof readPromptParams({ sessionId: "s", prompt: five }, "s"), "string");
  assert.equal(typeof readEditParams({ sessionId: "s", messageId: "m" }, "s"), "string");
});

test("the memory host: patches by id, appends chunks, coalesces nothing, retains the newest", async () => {
  const sessions = new MemorySessions({ retained: 2 });
  sessions.create("s", "jai");
  const adapter = sessions.adapter();
  const who = { login: "jai", name: null };
  sessions.apply("s", { sessionUpdate: "agent_message", messageId: "m1", content: [{ type: "text", text: "Look" }] });
  sessions.apply("s", {
    sessionUpdate: "agent_message_chunk",
    messageId: "m1",
    content: { type: "text", text: "ing" },
  });
  sessions.apply("s", { sessionUpdate: "agent_message", messageId: "m2", content: [{ type: "text", text: "Two" }] });
  sessions.apply("s", { sessionUpdate: "agent_message", messageId: "m3", content: [{ type: "text", text: "Three" }] });
  assert.deepEqual(sessions.message("s", "m1"), {
    sessionUpdate: "agent_message",
    messageId: "m1",
    content: [{ type: "text", text: "Looking" }],
  });
  const start = await adapter.read(who, "s", null);
  assert.ok(!start.expired);
  assert.deepEqual(
    start.updates.map((u) => (u.update as { messageId: string }).messageId),
    ["m2", "m3"],
  );
  const after = await adapter.read(who, "s", "1:1");
  assert.ok(!after.expired);
  assert.equal(after.updates.length, 3);
  assert.deepEqual(await adapter.read(who, "s", "1:99"), { expired: true });
  assert.deepEqual(await adapter.read(who, "s", "nonsense"), { expired: true });
});

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
  const source = join(import.meta.dirname, "..", "..", "protocol", "fixtures");
  const files = readdirSync(source).filter((name) => name.endsWith(".json"));
  assert.deepEqual(Object.keys(fixtures).sort(), files.map((name) => name.replace(/\.json$/, "")).sort());
  for (const name of files) {
    assert.deepEqual(fixtures[name.replace(/\.json$/, "")], JSON.parse(readFileSync(join(source, name), "utf8")), name);
  }
});
