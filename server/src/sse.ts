/**
 * Server-Sent Events on the session stream: each JSON-RPC message is one event, `data:` one line of JSON. A
 * `: keep-alive` comment every 15 s.
 */
import type { JsonRpcMessage } from "./acp.ts";

export const KEEP_ALIVE_MS = 15_000;
export const KEEP_ALIVE = ": keep-alive\n\n";

/** One message as an SSE event. `JSON.stringify` escapes line breaks inside strings, so `data` is one line. */
export function encodeEvent(message: JsonRpcMessage): string {
  return `data: ${JSON.stringify(message)}\n\n`;
}

/** What an SSE stream carried: a message, or a comment (the keep-alive). */
export type StreamItem = { message: JsonRpcMessage } | { comment: string };

/**
 * Parses SSE text as it arrives: `push` text, take the complete events. Lines of one event's `data` are joined with
 * newlines; `event`, `id` and `retry` lines are skipped.
 */
export class SSEParser {
  private buffer = "";

  push(text: string): StreamItem[] {
    this.buffer += text.replace(/\r\n?/g, "\n");
    const items: StreamItem[] = [];
    let end = this.buffer.indexOf("\n\n");
    while (end >= 0) {
      const block = this.buffer.slice(0, end);
      this.buffer = this.buffer.slice(end + 2);
      const data: string[] = [];
      for (const line of block.split("\n")) {
        if (line.startsWith(":")) {
          items.push({ comment: line.slice(1).trim() });
        } else if (line.startsWith("data:")) {
          data.push(line.slice(5).replace(/^ /, ""));
        }
      }
      if (data.length > 0) {
        items.push({ message: JSON.parse(data.join("\n")) as JsonRpcMessage });
      }
      end = this.buffer.indexOf("\n\n");
    }
    return items;
  }
}
