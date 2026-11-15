"""Writes protocol/fixtures/*.json, the golden fixtures of docs/live-protocol.md (our ACP v2 profile).

Run: python3 protocol/generate.py protocol/fixtures

A scenario has up to two halves:
- `server`: what the chat goes through (`before`, a resume, `during`), as ACP updates without cursors, and the updates
  the stream must then carry. Cursors are the host's, so the server side compares updates, not cursors. `resume`
  is "start", "@n" (the cursor after the n-th update of `before`) or "expired".
- `client`: JSON-RPC messages arriving on the session stream, and where the client ends.
"""
import json
import os
import sys

out = sys.argv[1]
os.makedirs(out, exist_ok=True)
T = "2026-11-15T05:00:%02d.000Z"
SID = "chat-1"
JAI = {"login": "jai", "name": "Jai"}


def ours(**kw):
    return {"agentchatkit": {k: v for k, v in kw.items()}}


def text(t):
    return [{"type": "text", "text": t}]


def user(id, t, s=0, status=None, ref=None, **kw):
    meta = {"at": None if s is None else T % s, "sender": JAI}
    if status:
        meta["status"] = status
    if ref:
        meta["clientRef"] = ref
    meta.update(kw)
    return {"sessionUpdate": "user_message", "messageId": id, "content": text(t), "_meta": {"agentchatkit": meta}}


def agent(id, t, s=0):
    return {"sessionUpdate": "agent_message", "messageId": id, "content": text(t),
            "_meta": ours(at=None if s is None else T % s)}


def tool(id, title, name, s=0):
    return {"sessionUpdate": "tool_call_update", "toolCallId": id, "title": title, "name": name, "kind": "execute",
            "status": "completed", "_meta": ours(at=None if s is None else T % s)}


def state(st, activity=None, problem=None, stop=None):
    u = {"sessionUpdate": "state_update", "state": st, "_meta": ours(activity=activity, problem=problem)}
    if stop:
        u["stopReason"] = stop
    return u


def note(update, cursor):
    return {"jsonrpc": "2.0", "method": "session/update",
            "params": {"sessionId": SID, "update": update, "_meta": ours(cursor=cursor)}}


def item(u):
    """What the client holds for an update, as the fixtures compare it."""
    kind = {"user_message": "user", "agent_message": "agent", "tool_call_update": "tool"}[u["sessionUpdate"]]
    t = u["title"] if kind == "tool" else u["content"][0]["text"]
    return {"id": u.get("messageId") or u["toolCallId"], "kind": kind, "text": t,
            "status": u["_meta"]["agentchatkit"].get("status")}


def expect(cursor, updates, st=None, question=None):
    return {"cursor": cursor, "messages": [item(u) for u in updates],
            "state": None if st is None else {"state": st["state"], "activity": st["_meta"]["agentchatkit"]["activity"]},
            "question": question}


def write(name, doc):
    with open(os.path.join(out, name), "w") as f:
        json.dump(doc, f, indent=2, ensure_ascii=False)
        f.write("\n")


m1 = user("m1", "Why is the build red?", 0, "delivered", "ref-1")
s2 = state("running", "Reading the CI log")
m3 = agent("m3", "A test times out on the simulator.", 5)
t4 = tool("t4", "swift test", "Bash", 6)
m5 = agent("m5", "I raised the timeout to 30 s.", 8)
s6 = state("idle", stop="end_turn")
QUESTION = {
    "jsonrpc": "2.0", "id": 900, "method": "elicitation/create",
    "params": {"sessionId": SID, "mode": "form", "message": "Merge now or wait for review?",
               "requestedSchema": {"type": "object", "properties": {
                   "choice": {"type": "string", "enum": ["merge", "wait"], "enumNames": ["Merge now", "Wait for review"]},
                   "text": {"type": "string", "description": "Anything to add"}}}}}

# --- messages.json: one of each message we use
write("messages.json", {
    "about": "Each JSON-RPC message the profile uses, with our _meta. Both sides decode and encode every one.",
    "client_to_host": [
        {"name": "initialize", "message": {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
            "protocolVersion": 2, "clientCapabilities": {"elicitation": {"form": {}}},
            "clientInfo": {"name": "AgentChatLive", "version": "0.3.0"}}}},
        {"name": "resume from start", "message": {"jsonrpc": "2.0", "id": 2, "method": "session/resume", "params": {
            "sessionId": SID, "cwd": "/", "replayFrom": {"type": "start"}}}},
        {"name": "resume from a cursor", "message": {"jsonrpc": "2.0", "id": 3, "method": "session/resume", "params": {
            "sessionId": SID, "cwd": "/", "replayFrom": {"type": "_cursor", "cursor": "c:2"}}}},
        {"name": "prompt", "message": {"jsonrpc": "2.0", "id": 4, "method": "session/prompt", "params": {
            "sessionId": SID, "prompt": text("Merge it.") + [{"type": "image", "mimeType": "image/jpeg", "data": "/9j/4AAQ"}],
            "_meta": ours(clientRef="ref-7", force=False)}}},
        {"name": "edit", "message": {"jsonrpc": "2.0", "id": 5, "method": "_agentchatkit/edit", "params": {
            "sessionId": SID, "messageId": "u7", "prompt": text("Merge it, then tag.")}}},
        {"name": "send now", "message": {"jsonrpc": "2.0", "id": 7, "method": "_agentchatkit/edit", "params": {
            "sessionId": SID, "messageId": "u7", "force": True}}},
        {"name": "remove", "message": {"jsonrpc": "2.0", "id": 6, "method": "_agentchatkit/remove", "params": {
            "sessionId": SID, "messageId": "u8"}}},
        {"name": "answer", "message": {"jsonrpc": "2.0", "id": 900, "result": {
            "action": "accept", "content": {"choice": "merge", "text": "and tag it"}}}},
    ],
    "host_to_client": [
        {"name": "initialized", "message": {"jsonrpc": "2.0", "id": 1, "result": {
            "protocolVersion": 2, "agentCapabilities": {"loadSession": True},
            "agentInfo": {"name": "agentchat-live", "version": "0.3.0"}}}},
        {"name": "user message", "message": note(dict(m1, content=m1["content"] + [{
            "type": "resource_link", "name": "screenshot.jpg", "uri": "acp/attachments/a1?sig=abc",
            "mimeType": "image/jpeg", "size": 412803, "_meta": ours(width=1179, height=2556, durationMs=None)}]), "c:1")},
        {"name": "state", "message": note(s2, "c:2")},
        {"name": "agent message", "message": note(m3, "c:3")},
        {"name": "agent message chunk", "message": note({"sessionUpdate": "agent_message_chunk", "messageId": "m9",
                                                         "content": {"type": "text", "text": "Looking at"}}, "c:4")},
        {"name": "tool call", "message": note(t4, "c:5")},
        {"name": "model and reasoning", "message": note({"sessionUpdate": "config_option_update", "configOptions": [
            {"id": "model", "name": "Model", "type": "select", "currentValue": "claude-opus-5-5",
             "options": [{"value": "claude-opus-5-5", "name": "Claude Opus 5.5"}]}]}, "c:6")},
        {"name": "question", "message": QUESTION},
        {"name": "prompt taken", "message": {"jsonrpc": "2.0", "id": 4, "result": {"messageId": "u7"}}},
        {"name": "cursor expired", "message": {"jsonrpc": "2.0", "id": 3, "error": {
            "code": -32602, "message": "cursor expired"}}},
        {"name": "not queued any more", "message": {"jsonrpc": "2.0", "id": 5, "error": {
            "code": -32009, "message": "conflict"}}},
        {"name": "question taken elsewhere", "message": {"jsonrpc": "2.0", "method": "$/cancel_request",
                                                          "params": {"requestId": 900}}},
    ],
})

# --- resume-start
write("resume-start.json", {
    "about": "No cursor held: resume from start replays the retained history, then the current state, then live updates.",
    "server": {"before": [m1, s2, m3], "resume": "start", "during": [t4],
               "stream": [m1, m3, s2, t4]},
    "client": {"start": None,
               "messages": [note(m1, "c:1"), note(m3, "c:3"), note(s2, "c:3"), note(t4, "c:4")],
               "expect": expect("c:4", [m1, m3, t4], s2)},
})

# --- resume-cursor
write("resume-cursor.json", {
    "about": "Resume from the cursor after update 2: only what came after it, the current state, then live updates.",
    "server": {"before": [m1, s2, m3], "resume": "@2", "during": [m5],
               "stream": [m3, s2, m5]},
    "client": {"start": {"cursor": "c:2", "messages": [m1], "state": s2},
               "messages": [note(m3, "c:3"), note(s2, "c:3"), note(m5, "c:4"), note(s6, "c:5")],
               "expect": expect("c:5", [m1, m3, m5], s6)},
})

# --- resume-expired
n1 = agent("n1", "A fresh session: the transcript was replaced.", 30)
write("resume-expired.json", {
    "about": "A cursor the host can't resume from answers -32602; the client resumes from start, and the replay "
             "replaces everything it held.",
    "server": {"before": [m1, s2, m3], "resume": "expired", "error": -32602},
    "client": {"start": {"cursor": "c:9", "messages": [m1, m3, m5], "state": s2},
               "error": -32602,
               "replay": [note(n1, "e2:1"), note(state("idle", stop="end_turn"), "e2:1")],
               "expect": expect("e2:1", [n1], state("idle", stop="end_turn"))},
})

# --- display-order
u2 = user("u2", "Also check the iPad.", 10, "pending", "ref-u2")
a2 = agent("a2", "The iPhone run is green.", 8)
t9 = tool("t9", "xcodebuild test", "Bash", None)
write("display-order.json", {
    "about": "By `at`, not arrival: a2 (:08) arrives after u2 (:10) and goes before it. t9 has no `at`: it sorts at "
             "the `at` of the message before it when first taken. Equal `at` keeps the order taken.",
    "client": {"start": {"cursor": "c:1", "messages": [m1], "state": None},
               "messages": [note(u2, "c:2"), note(a2, "c:3"), note(t9, "c:4")],
               "expect": expect("c:4", [m1, a2, u2, t9])},
})

# --- prompt-lifecycle
q1 = user("u7", "Merge it.", 10, "queued", "ref-7")
q2 = user("u7", "Merge it, then tag.", 10, "queued", "ref-7")
qf = user("u7", "Merge it, then tag.", 10, "pending", "ref-7")
q3 = user("u7", "Merge it, then tag.", 10, "delivering", "ref-7")
q4 = user("u7", "Merge it, then tag.", 10, "delivered", "ref-7")
r1 = user("u8", "Never mind.", 11, "queued", "ref-8")
r2 = user("u8", "Never mind.", 11, "removed", "ref-8")
write("prompt-lifecycle.json", {
    "about": "Prompts sent while the agent works: inserted at once as queued, edited, then forced (send it now: "
             "queued becomes pending), delivered; another "
             "removed. A repeat clientRef answers the first messageId and adds nothing. A removed message stays held "
             "(its status is known) but has no bubble.",
    "server": {
        "before": [m1, state("running", "Running tests")], "resume": "@2",
        "writes": [
            {"request": {"method": "session/prompt", "params": {"sessionId": SID, "prompt": text("Merge it."),
                                                                "_meta": ours(clientRef="ref-7", force=False)}},
             "result": {"messageId": "@u7"}, "stream": [q1]},
            {"request": {"method": "session/prompt", "params": {"sessionId": SID, "prompt": text("Merge it."),
                                                                "_meta": ours(clientRef="ref-7", force=False)}},
             "result": {"messageId": "@u7"}, "stream": []},
            {"request": {"method": "_agentchatkit/edit", "params": {"sessionId": SID, "messageId": "@u7",
                                                                    "prompt": text("Merge it, then tag.")}},
             "result": {"messageId": "@u7"}, "stream": [q2]},
            {"request": {"method": "_agentchatkit/edit", "params": {"sessionId": SID, "messageId": "@u7",
                                                                    "force": True}},
             "result": {"messageId": "@u7"}, "stream": [qf]},
            {"request": {"method": "session/prompt", "params": {"sessionId": SID, "prompt": text("Never mind."),
                                                                "_meta": ours(clientRef="ref-8", force=False)}},
             "result": {"messageId": "@u8"}, "stream": [r1]},
            {"request": {"method": "_agentchatkit/remove", "params": {"sessionId": SID, "messageId": "@u8"}},
             "result": {"messageId": "@u8"}, "stream": [r2]},
            {"request": {"method": "_agentchatkit/remove", "params": {"sessionId": SID, "messageId": "@u8"}},
             "error": -32009, "stream": []},
        ],
    },
    "client": {"start": {"cursor": "c:2", "messages": [m1], "state": None},
               "messages": [note(q1, "c:3"), note(q2, "c:4"), note(qf, "c:5"), note(q3, "c:6"), note(q4, "c:7"),
                            note(r1, "c:8"), note(r2, "c:9")],
               "expect": expect("c:9", [m1, q4, r2]),
               "bubbles": ["m1", "u7"], "ticks": {"u7": 2}},
})

# --- question
ans = user("u12", "Merge now: and tag it", 42, "pending")
write("question.json", {
    "about": "The agent asks. Both clients get elicitation/create and the state turns requires_action. Client A "
             "answers; the host cancels the request on client B, shows the answer as a user message, and moves on.",
    "server": {
        "before": [m1, state("running", "Checking CI")], "clients": 2, "ask": QUESTION["params"],
        "stream_both": ["elicitation/create", state("requires_action")],
        "answer_from": 0, "answer": {"action": "accept", "content": {"choice": "merge", "text": "and tag it"}},
        "to_other": "$/cancel_request",
        "then": [ans, state("running", "Merging")],
    },
    "client": {"start": {"cursor": "c:2", "messages": [m1], "state": None},
               "messages": [QUESTION, note(state("requires_action"), "c:3")],
               "expect": expect("c:3", [m1], state("requires_action"), question=900),
               "then": [{"jsonrpc": "2.0", "method": "$/cancel_request", "params": {"requestId": 900}},
                        note(ans, "c:4"), note(state("running", "Merging"), "c:5")],
               "expect_then": expect("c:5", [m1, ans], state("running", "Merging"), question=None)},
})

# --- transport
write("transport.json", {
    "about": "What the client does on each HTTP answer and when the stream ends; the back-off and keep-alive.",
    "statuses": [
        {"status": 202, "action": "wait for the answer on the stream"},
        {"status": 200, "action": "follow"},
        {"status": 401, "action": "reauth"},
        {"status": 403, "action": "stop"},
        {"status": 404, "action": "initialize again", "about": "a connection id the server no longer knows"},
        {"status": 500, "action": "reconnect"},
        {"status": 503, "action": "reconnect"},
    ],
    "ended": {"about": "the stream ends, or nothing heard for quiet_limit_ms", "action": "reconnect"},
    "backoff_ms": [1000, 2000, 4000, 8000, 15000, 15000],
    "jitter": 0.2,
    "backoff_resets_after_ms": 10000,
    "keep_alive_ms": 15000,
    "quiet_limit_ms": 40000,
    "retained_messages": 200,
    "headers": {"connection": "Acp-Connection-Id", "session": "Acp-Session-Id"},
})
print("fixtures written")
