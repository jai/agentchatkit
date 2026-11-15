// The conformance suite against the in-memory host, as a host runs it in its own CI; and again as a host that never
// queues and takes no questions (FeedbackKit's shape), so the capability skips are exercised too.
import { describe, test } from "node:test";
import { type ConformanceHarness, conformanceCases, type HostCapabilities } from "../src/conformance.ts";
import { MemorySessions, type MemoryWho } from "../src/memory.ts";

function harness(capabilities: HostCapabilities): ConformanceHarness<MemoryWho> {
  const sessions = new MemorySessions({ queues: capabilities.queues, names: { jai: "Jai" } });
  const full = sessions.adapter();
  const adapter = capabilities.answer ? full : { ...full, answer: undefined };
  let count = 0;
  return {
    adapter,
    capabilities,
    reset: async () => {
      count += 1;
      const id = `chat-${count}`;
      sessions.create(id, "jai");
      return id;
    },
    apply: async (id, update) => {
      sessions.apply(id, update);
    },
    ask: async (id, params) => {
      sessions.ask(id, params);
    },
    expire: async (id) => sessions.expire(id),
    request: (url, init = {}, auth = "owner") => {
      const headers = new Headers(init.headers);
      if (auth !== "none") {
        headers.set("Authorization", `Bearer token-${auth === "owner" ? "jai" : "someone-else"}`);
      }
      return new Request(url, { ...init, headers });
    },
  };
}

const hosts: [string, HostCapabilities][] = [
  ["a host that queues and asks", { queues: true, edit: true, remove: true, answer: true }],
  ["a host that never queues and asks nothing", { queues: false, edit: true, remove: true, answer: false }],
];

for (const [name, capabilities] of hosts) {
  describe(name, () => {
    const cases = conformanceCases(harness(capabilities));
    for (const c of cases) {
      test(c.name, { skip: c.skip }, c.run);
    }
  });
}
