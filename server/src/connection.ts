/**
 * Connection ids. The Worker keeps no state between requests, so an `Acp-Connection-Id` is signed: `initialize`
 * mints one, and every later request proves it with the host's secret. One the server did not mint, or that has
 * run out (24 h), is unknown: `404`, and the client starts again from `initialize`.
 */

export const CONNECTION_LIFETIME_MS = 24 * 60 * 60 * 1000;

const encoder = new TextEncoder();

function base64url(bytes: ArrayBuffer | Uint8Array): string {
  let text = "";
  for (const byte of new Uint8Array(bytes)) {
    text += String.fromCharCode(byte);
  }
  return btoa(text).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function sign(secret: string, payload: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, [
    "sign",
  ]);
  return base64url(await crypto.subtle.sign("HMAC", key, encoder.encode(payload)));
}

/** A new connection id: random, when it runs out, and their signature. */
export async function mintConnection(secret: string, now: number): Promise<string> {
  const random = base64url(crypto.getRandomValues(new Uint8Array(16)));
  const payload = `${random}.${(now + CONNECTION_LIFETIME_MS).toString(36)}`;
  return `${payload}.${await sign(secret, payload)}`;
}

/** Whether this server minted the id, and it has not run out. Compared in constant time. */
export async function verifyConnection(secret: string, id: string, now: number): Promise<boolean> {
  const parts = id.split(".");
  if (parts.length !== 3 || !parts[0] || !parts[1] || !parts[2]) {
    return false;
  }
  const expires = parseInt(parts[1], 36);
  if (!Number.isFinite(expires) || expires <= now) {
    return false;
  }
  const expected = await sign(secret, `${parts[0]}.${parts[1]}`);
  if (expected.length !== parts[2].length) {
    return false;
  }
  let differ = 0;
  for (let index = 0; index < expected.length; index += 1) {
    differ |= expected.charCodeAt(index) ^ parts[2].charCodeAt(index);
  }
  return differ === 0;
}
