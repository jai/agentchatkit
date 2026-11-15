/**
 * The JSON-RPC 2.0 and ACP v2 shapes our profile uses (docs/live-protocol.md in jai/agentchatkit), with our
 * `_meta.agentchatkit` fields. Only what the profile uses: the spec holds the rest.
 */

export const PROTOCOL_VERSION = 2;

/** JSON-RPC and ACP error codes the profile answers. */
export const ERRORS = {
  parse: -32700,
  invalidRequest: -32600,
  methodNotFound: -32601,
  /** Bad params, and a cursor the host can no longer resume from. */
  invalidParams: -32602,
  internal: -32603,
  /** A message no longer `pending` or `queued`. */
  conflict: -32009,
} as const;

// --- JSON-RPC

export type RequestId = string | number;

export interface JsonRpcRequest<Method extends string = string, Params = unknown> {
  jsonrpc: "2.0";
  id: RequestId;
  method: Method;
  params: Params;
}

export interface JsonRpcNotification<Method extends string = string, Params = unknown> {
  jsonrpc: "2.0";
  method: Method;
  params: Params;
}

export interface JsonRpcSuccess<Result = unknown> {
  jsonrpc: "2.0";
  id: RequestId;
  result: Result;
}

export interface JsonRpcError {
  jsonrpc: "2.0";
  id: RequestId | null;
  error: { code: number; message: string; data?: unknown };
}

export type JsonRpcMessage = JsonRpcRequest | JsonRpcNotification | JsonRpcSuccess | JsonRpcError;

// --- Our _meta

export type MessageStatus = "pending" | "queued" | "delivering" | "delivered" | "failed" | "removed";

export interface Sender {
  login: string;
  name: string | null;
}

/** `_meta.agentchatkit`: every key optional; which apply where is in the doc's tables. */
export interface AgentChatMeta {
  at?: string | null;
  sender?: Sender;
  status?: MessageStatus;
  clientRef?: string;
  detail?: string | null;
  activity?: string | null;
  problem?: string | null;
  force?: boolean;
  cursor?: string;
  width?: number | null;
  height?: number | null;
  durationMs?: number | null;
  extra?: Record<string, unknown>;
}

export interface Meta {
  agentchatkit?: AgentChatMeta;
  [key: string]: unknown;
}

// --- Content

export interface TextBlock {
  type: "text";
  text: string;
  _meta?: Meta;
}

export interface ImageBlock {
  type: "image";
  mimeType: string;
  data: string;
  _meta?: Meta;
}

export interface ResourceLinkBlock {
  type: "resource_link";
  name: string;
  uri: string;
  mimeType?: string;
  size?: number;
  _meta?: Meta;
}

export type ContentBlock = TextBlock | ImageBlock | ResourceLinkBlock;

// --- Session updates

export interface UserMessageUpdate {
  sessionUpdate: "user_message";
  messageId: string;
  content: ContentBlock[];
  _meta?: Meta;
}

export interface AgentMessageUpdate {
  sessionUpdate: "agent_message";
  messageId: string;
  content: ContentBlock[];
  _meta?: Meta;
}

export interface AgentMessageChunkUpdate {
  sessionUpdate: "agent_message_chunk";
  messageId: string;
  content: ContentBlock;
  _meta?: Meta;
}

export interface ToolCallUpdate {
  sessionUpdate: "tool_call_update";
  toolCallId: string;
  title?: string;
  name?: string;
  kind?: string;
  status?: "pending" | "in_progress" | "completed" | "failed";
  _meta?: Meta;
  [key: string]: unknown;
}

export type SessionState = "running" | "idle" | "requires_action";

export interface StateUpdate {
  sessionUpdate: "state_update";
  state: SessionState;
  stopReason?: string;
  _meta?: Meta;
}

export interface ConfigOption {
  id: string;
  name: string;
  type: "select";
  currentValue: string;
  options: { value: string; name: string }[];
}

export interface ConfigOptionUpdate {
  sessionUpdate: "config_option_update";
  configOptions: ConfigOption[];
  _meta?: Meta;
}

export type SessionUpdate =
  | UserMessageUpdate
  | AgentMessageUpdate
  | AgentMessageChunkUpdate
  | ToolCallUpdate
  | StateUpdate
  | ConfigOptionUpdate;

export interface SessionUpdateParams {
  sessionId: string;
  update: SessionUpdate;
  _meta: { agentchatkit: { cursor: string } };
}

// --- Methods

export interface InitializeParams {
  protocolVersion: number;
  clientCapabilities?: { elicitation?: { form?: Record<string, never> } } & Record<string, unknown>;
  clientInfo?: { name: string; version: string };
}

export interface InitializeResult {
  protocolVersion: number;
  agentCapabilities: { loadSession: boolean };
  agentInfo: { name: string; version: string };
}

export type ReplayFrom = { type: "start" } | { type: "_cursor"; cursor: string };

export interface ResumeParams {
  sessionId: string;
  cwd?: string;
  replayFrom?: ReplayFrom;
}

export interface PromptParams {
  sessionId: string;
  prompt: ContentBlock[];
  _meta?: { agentchatkit?: { clientRef?: string; force?: boolean } };
}

export interface EditParams {
  sessionId: string;
  messageId: string;
  prompt?: ContentBlock[];
  force?: boolean;
}

export interface RemoveParams {
  sessionId: string;
  messageId: string;
}

/** A write's answer: the message it made or changed. */
export interface MessageIdResult {
  messageId: string;
}

export interface ElicitationCreateParams {
  sessionId: string;
  mode: "form";
  message: string;
  requestedSchema: {
    type: "object";
    properties: Record<string, Record<string, unknown>>;
    required?: string[];
  };
}

export interface ElicitationResult {
  action: "accept" | "decline" | "cancel";
  content?: Record<string, unknown>;
}

export interface CancelRequestParams {
  requestId: RequestId;
}

// --- Builders

export function notification<Params>(method: string, params: Params): JsonRpcNotification<string, Params> {
  return { jsonrpc: "2.0", method, params };
}

export function success<Result>(id: RequestId, result: Result): JsonRpcSuccess<Result> {
  return { jsonrpc: "2.0", id, result };
}

export function failure(id: RequestId | null, code: number, message: string): JsonRpcError {
  return { jsonrpc: "2.0", id, error: { code, message } };
}

/** A `session/update` with its cursor on the notification's `_meta`, never on the update. */
export function sessionUpdate(sessionId: string, update: SessionUpdate, cursor: string) {
  return notification<SessionUpdateParams>("session/update", {
    sessionId,
    update,
    _meta: { agentchatkit: { cursor } },
  });
}

// --- Reading what a client sends

export function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export type Incoming =
  | { kind: "request"; message: JsonRpcRequest }
  | { kind: "notification"; message: JsonRpcNotification }
  | { kind: "response"; message: JsonRpcSuccess | JsonRpcError }
  | { kind: "invalid"; error: JsonRpcError };

/** One JSON-RPC message, sorted: a request, a notification, a response (to our `elicitation/create`), or invalid. */
export function readIncoming(body: unknown): Incoming {
  if (!isObject(body) || body.jsonrpc !== "2.0") {
    return { kind: "invalid", error: failure(null, ERRORS.invalidRequest, "one JSON-RPC 2.0 message, please") };
  }
  const id = body.id;
  const hasId = typeof id === "string" || typeof id === "number";
  if (typeof body.method === "string") {
    const params = body.params ?? {};
    return hasId
      ? { kind: "request", message: { jsonrpc: "2.0", id, method: body.method, params } }
      : { kind: "notification", message: { jsonrpc: "2.0", method: body.method, params } };
  }
  if (hasId && ("result" in body || "error" in body)) {
    return { kind: "response", message: body as unknown as JsonRpcSuccess | JsonRpcError };
  }
  return { kind: "invalid", error: failure(hasId ? id : null, ERRORS.invalidRequest, "neither a request nor a response") };
}

function isContent(value: unknown): value is ContentBlock {
  if (!isObject(value)) {
    return false;
  }
  switch (value.type) {
    case "text":
      return typeof value.text === "string";
    case "image":
      return typeof value.mimeType === "string" && typeof value.data === "string";
    case "resource_link":
      return typeof value.uri === "string" && typeof value.name === "string";
    default:
      return false;
  }
}

/** The most `image` blocks a prompt may carry (`MessageImage.limit`). */
export const MAX_IMAGES = 4;

/** A prompt's blocks, or why not. */
export function readPrompt(value: unknown): ContentBlock[] | string {
  if (!Array.isArray(value) || value.length === 0 || !value.every(isContent)) {
    return "prompt is a non-empty list of text, image and resource_link blocks";
  }
  if (value.filter((block) => block.type === "image").length > MAX_IMAGES) {
    return `at most ${MAX_IMAGES} images`;
  }
  return value;
}

export function readResume(params: unknown, sessionId: string): ResumeParams | string {
  if (!isObject(params) || params.sessionId !== sessionId) {
    return "sessionId is the stream's Acp-Session-Id";
  }
  const replay = params.replayFrom;
  if (replay === undefined || (isObject(replay) && replay.type === "start")) {
    return { sessionId, replayFrom: { type: "start" } };
  }
  if (isObject(replay) && replay.type === "_cursor" && typeof replay.cursor === "string") {
    return { sessionId, replayFrom: { type: "_cursor", cursor: replay.cursor } };
  }
  return 'replayFrom is {"type": "start"} or {"type": "_cursor", "cursor": string}';
}

export function readPromptParams(params: unknown, sessionId: string): PromptParams | string {
  if (!isObject(params) || params.sessionId !== sessionId) {
    return "sessionId is the stream's Acp-Session-Id";
  }
  const prompt = readPrompt(params.prompt);
  if (typeof prompt === "string") {
    return prompt;
  }
  const ours = isObject(params._meta) && isObject(params._meta.agentchatkit) ? params._meta.agentchatkit : {};
  if (ours.clientRef !== undefined && (typeof ours.clientRef !== "string" || ours.clientRef === "")) {
    return "clientRef is a non-empty string";
  }
  if (ours.force !== undefined && typeof ours.force !== "boolean") {
    return "force is a bool";
  }
  const meta: { clientRef?: string; force?: boolean } = {};
  if (typeof ours.clientRef === "string") {
    meta.clientRef = ours.clientRef;
  }
  if (typeof ours.force === "boolean") {
    meta.force = ours.force;
  }
  return { sessionId, prompt, _meta: { agentchatkit: meta } };
}

export function readEditParams(params: unknown, sessionId: string): EditParams | string {
  if (!isObject(params) || params.sessionId !== sessionId || typeof params.messageId !== "string") {
    return "sessionId is the stream's Acp-Session-Id, and messageId a string";
  }
  const edit: EditParams = { sessionId, messageId: params.messageId };
  if (params.prompt !== undefined) {
    const prompt = readPrompt(params.prompt);
    if (typeof prompt === "string") {
      return prompt;
    }
    edit.prompt = prompt;
  }
  if (params.force !== undefined) {
    if (typeof params.force !== "boolean") {
      return "force is a bool";
    }
    edit.force = params.force;
  }
  if (edit.prompt === undefined && edit.force === undefined) {
    return "an edit changes prompt, force, or both";
  }
  return edit;
}

export function readRemoveParams(params: unknown, sessionId: string): RemoveParams | string {
  if (!isObject(params) || params.sessionId !== sessionId || typeof params.messageId !== "string") {
    return "sessionId is the stream's Acp-Session-Id, and messageId a string";
  }
  return { sessionId, messageId: params.messageId };
}

export function readElicitationResult(result: unknown): ElicitationResult | string {
  if (!isObject(result) || !["accept", "decline", "cancel"].includes(result.action as string)) {
    return "action is accept, decline or cancel";
  }
  if (result.content !== undefined && !isObject(result.content)) {
    return "content is an object";
  }
  return result.content === undefined
    ? { action: result.action as ElicitationResult["action"] }
    : { action: result.action as ElicitationResult["action"], content: result.content };
}
