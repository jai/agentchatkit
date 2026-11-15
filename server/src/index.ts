/**
 * @jai/agentchat-live: our ACP v2 profile's server (docs/live-protocol.md in jai/agentchatkit).
 *
 * A host Worker gives an adapter (`LiveAdapter`), binds the room (`createLiveRoom`), mounts `<base>/acp` on
 * `handleAcp`, and calls `notifyChat` when a session changes. The conformance suite is
 * `@jai/agentchat-live/conformance`; an in-memory host is `@jai/agentchat-live/memory`.
 */
export * from "./acp.ts";
export * from "./adapter.ts";
export { CONNECTION_LIFETIME_MS, mintConnection, verifyConnection } from "./connection.ts";
export { type AcpRoute, CONNECTION_HEADER, handleAcp, PACKAGE_VERSION, SESSION_HEADER } from "./handler.ts";
export {
  closeConnection,
  createLiveRoom,
  LiveRoom,
  type LiveRoomOptions,
  type LiveRooms,
  notifyChat,
  notifyQuestion,
  openStream,
  platformTimers,
  postToRoom,
  type RoomTimers,
} from "./room.ts";
export { encodeEvent, KEEP_ALIVE, KEEP_ALIVE_MS, SSEParser, type StreamItem } from "./sse.ts";
