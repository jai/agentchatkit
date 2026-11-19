// The parts: connection ids, SSE, reading a client's messages, the memory host, the handler's edges, and that the
// embedded fixtures are protocol/fixtures as they stand.
import assert from "node:assert/strict";
import { test } from "node:test";
import { readEditParams, readIncoming, readPromptParams, readResume, sessionUpdate } from "../../src/acp.ts";
import { CONNECTION_LIFETIME_MS, mintConnection, verifyConnection } from "../../src/connection.ts";
import { MemorySessions } from "../../src/memory.ts";
import { encodeEvent, SSEParser } from "../../src/sse.ts";

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
