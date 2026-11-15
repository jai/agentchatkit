/**
 * `<base>/acp`: ACP's Streamable HTTP transport, as our profile uses it (docs/live-protocol.md#transport).
 *
 * - `POST initialize` (no `Acp-Connection-Id`): `200`, the result in the body, and `Acp-Connection-Id`.
 * - Other `POST`s (`Acp-Connection-Id` and `Acp-Session-Id`): `202`; the answer comes on the session stream.
 * - `GET` with both headers: the session stream, held by the session's room.
 * - `DELETE` with `Acp-Connection-Id`: `202`, and the connection's stream in that session ends.
 *
 * ```ts
 * app.all("/v2/acp", (c) => handleAcp(c.req.raw, { adapter, rooms: c.env.LIVE_ROOMS, secret: c.env.ACP_SECRET }));
 * ```
 */
import {
  ERRORS,
  failure,
  type InitializeResult,
  isObject,
  PROTOCOL_VERSION,
  readIncoming,
  success,
} from "./acp.ts";
import { isRefusal, type LiveAdapter } from "./adapter.ts";
import { mintConnection, verifyConnection } from "./connection.ts";
import { closeConnection, type LiveRooms, openStream, postToRoom } from "./room.ts";

export const CONNECTION_HEADER = "Acp-Connection-Id";
export const SESSION_HEADER = "Acp-Session-Id";

export interface AcpRoute<Who> {
  adapter: LiveAdapter<Who>;
  /** The room namespace: a Durable Object binding of `createLiveRoom`'s class. */
  rooms: LiveRooms;
  /** Signs connection ids. Any long random string; changing it ends every connection (they initialize again). */
  secret: string;
  /** Who answers `initialize`. `agentchat-live` and the package's version. */
  agentInfo?: { name: string; version: string };
  /** The clock, for connection ids. `Date.now`. */
  now?: () => number;
}

export const PACKAGE_VERSION = "0.0.0";

function plain(status: number, message: string, headers: Record<string, string> = {}): Response {
  return Response.json({ error: message }, { status, headers: { "Cache-Control": "no-store", ...headers } });
}

/** Serves one request to `<base>/acp`. Never throws: a failure is `500`. */
export async function handleAcp<Who>(request: Request, route: AcpRoute<Who>): Promise<Response> {
  try {
    return await serve(request, route);
  } catch (error) {
    console.error("agentchat-live: request failed", error);
    return plain(500, "the server failed");
  }
}

async function serve<Who>(request: Request, route: AcpRoute<Who>): Promise<Response> {
  const now = (route.now ?? Date.now)();
  const connection = request.headers.get(CONNECTION_HEADER);
  const sessionId = request.headers.get(SESSION_HEADER);

  if (request.method === "POST") {
    if (!(request.headers.get("Content-Type") ?? "").toLowerCase().startsWith("application/json")) {
      return plain(415, "POST application/json");
    }
    const body: unknown = await request.json().catch(() => undefined);
    if (body === undefined) {
      return Response.json(failure(null, ERRORS.parse, "not JSON"), { status: 400 });
    }
    if (Array.isArray(body)) {
      return Response.json(failure(null, ERRORS.invalidRequest, "one message per request: no batches"), { status: 400 });
    }
    if (connection === null) {
      if (isObject(body) && body.method === "initialize") {
        return initialize(body, route, now);
      }
      return plain(400, `${CONNECTION_HEADER} is required after initialize`);
    }
    if (!(await verifyConnection(route.secret, connection, now))) {
      return plain(404, "unknown connection: initialize again");
    }
    if (sessionId === null) {
      return plain(400, `${SESSION_HEADER} is required: every method here is the session's`);
    }
    const incoming = readIncoming(body);
    if (incoming.kind === "invalid") {
      return Response.json(incoming.error, { status: 400 });
    }
    const who = await route.adapter.authorize(request, sessionId);
    if (isRefusal(who)) {
      return plain(who.refusal.status, who.refusal.message);
    }
    const answer = await postToRoom(route.rooms, sessionId, connection, who, body);
    await answer.body?.cancel();
    return new Response(null, { status: 202 });
  }

  if (request.method === "GET") {
    if (connection === null) {
      return plain(400, `${CONNECTION_HEADER} is required`);
    }
    if (!(request.headers.get("Accept") ?? "").includes("text/event-stream")) {
      return plain(406, "Accept: text/event-stream");
    }
    if (!(await verifyConnection(route.secret, connection, now))) {
      return plain(404, "unknown connection: initialize again");
    }
    if (sessionId === null) {
      return plain(400, `this profile has no connection stream: open the session's, with ${SESSION_HEADER}`);
    }
    const who = await route.adapter.authorize(request, sessionId);
    if (isRefusal(who)) {
      return plain(who.refusal.status, who.refusal.message);
    }
    return openStream(route.rooms, sessionId, connection, who);
  }

  if (request.method === "DELETE") {
    if (connection === null) {
      return plain(400, `${CONNECTION_HEADER} is required`);
    }
    if (sessionId !== null && (await verifyConnection(route.secret, connection, now))) {
      const answer = await closeConnection(route.rooms, sessionId, connection);
      await answer.body?.cancel();
    }
    return new Response(null, { status: 202 });
  }

  return plain(405, "GET, POST or DELETE", { Allow: "GET, POST, DELETE" });
}

async function initialize<Who>(body: Record<string, unknown>, route: AcpRoute<Who>, now: number): Promise<Response> {
  const id = body.id;
  if (typeof id !== "string" && typeof id !== "number") {
    return Response.json(failure(null, ERRORS.invalidRequest, "initialize is a request: it needs an id"), {
      status: 400,
    });
  }
  const connection = await mintConnection(route.secret, now);
  const result: InitializeResult = {
    protocolVersion: PROTOCOL_VERSION,
    agentCapabilities: { loadSession: true },
    agentInfo: route.agentInfo ?? { name: "agentchat-live", version: PACKAGE_VERSION },
  };
  return Response.json(success(id, result), {
    headers: { [CONNECTION_HEADER]: connection, "Cache-Control": "no-store" },
  });
}
