import json, os, sys
# Writes protocol/fixtures/*.json, the golden fixtures of docs/live-protocol.md. Run: python3 protocol/generate.py protocol/fixtures
out = sys.argv[1]
os.makedirs(out, exist_ok=True)
T = "2026-11-15T05:00:%02d.000Z"
JAI = {"login": "jai", "name": "Jai"}
SHOT = {"id": "img1", "url": "images/img1?sig=abc", "media_type": "image/jpeg", "width": 1179, "height": 2556}
def msg(id, seq, role, text, s=0, **kw):
    m = {"id": id, "seq": seq, "role": role, "text": text, "at": T % s, "tool": None, "partial": False,
         "reply_id": None, "images": [], "sender": JAI if role == "user" else None}
    m.update(kw); return m
def reply(id, seq, status, text, s=0, **kw):
    r = {"id": id, "seq": seq, "client_ref": "ref-" + id, "status": status, "text": text, "at": T % s,
         "detail": None, "message_id": None, "sender": JAI, "images": []}
    r.update(kw); return r
def state(seq, working, activity=None, **kw):
    s = {"seq": seq, "working": working, "activity": activity, "problem": None, "model": "claude-opus-5-5",
         "effort": "high", "waiting": None}
    s.update(kw); return s
def cur(n): return "c:%d" % n
def hello(seq, resumed, chat="chat-1"): return {"type": "hello", "v": 1, "chat": chat, "cursor": cur(seq), "seq": seq, "resumed": resumed}
def f_msg(m): return {"type": "message", "cursor": cur(m["seq"]), "seq": m["seq"], "message": m}
def f_reply(r): return {"type": "reply", "cursor": cur(r["seq"]), "seq": r["seq"], "reply": r}
def f_state(s): return {"type": "state", "cursor": cur(s["seq"]), "seq": s["seq"], "state": s}
def snap(seq, messages, replies, st, more=False):
    return {"type": "snapshot", "cursor": cur(seq), "seq": seq, "messages": messages, "replies": replies, "state": st, "more_before": more}
def strip(item):
    """What the server side compares: everything but the host-assigned seq."""
    return {k: v for k, v in item.items() if k != "seq"}
def sse(frame):
    lines = ["event: " + frame["type"]]
    if "cursor" in frame: lines.append("id: " + frame["cursor"])
    lines.append("data: " + json.dumps(frame, separators=(",", ":"), ensure_ascii=False))
    return "\n".join(lines) + "\n\n"
def expect(cursor, seq, messages, replies, st, more=False):
    return {"cursor": cursor, "seq": seq,
            "messages": [{"id": m["id"], "seq": m["seq"], "text": m["text"], "partial": m["partial"]} for m in messages],
            "replies": [{"id": r["id"], "seq": r["seq"], "status": r["status"], "message_id": r["message_id"]} for r in replies],
            "state": None if st is None else {"seq": st["seq"], "working": st["working"], "activity": st["activity"], "waiting": None if st.get("waiting") is None else st["waiting"]["id"]},
            "more_before": more}
def ch(kind, item): return {kind: strip(item)}
def write(name, doc):
    with open(os.path.join(out, name), "w") as f:
        json.dump(doc, f, indent=2, ensure_ascii=False); f.write("\n")

empty_state = state(0, False, model=None, effort=None)

# --- frames.json: one of each frame, as JSON and SSE text
m7 = msg("m7", 42, "assistant", "Done. **Tests pass.**", 2)
r1 = reply("rpl_1", 40, "delivered", "Merge it once CI is green.", 0, message_id="m6")
s41 = state(41, True, "Running tests")
s43 = state(43, False, None, waiting={"id": "q1", "question": "Merge now or wait for review?", "options": [{"id": "merge", "label": "Merge now"}, {"id": "wait", "label": "Wait for review"}], "multiple": False, "free_text": True})
frames = [
    hello(41, True),
    snap(41, [msg("m6", 40, "user", "Merge it once CI is green.", 0, reply_id="rpl_1", images=[SHOT]),
              msg("t1", 39, "tool", "swift test", 1, tool="Bash")], [r1], s41, True),
    f_msg(m7), f_reply(r1), f_state(s41), f_state(s43),
    {"type": "ping"},
    {"type": "close", "code": 4000, "reason": "rotate", "retry_after_ms": 0},
    {"type": "earlier", "messages": [msg("m1", 1, "user", "Hello", 0)], "more_before": False},
]
write("frames.json", {
    "about": "One of each frame type (docs/live-protocol.md#frames), as its JSON and as the SSE text the server sends. Both sides encode and decode every one.",
    "frames": [{"json": f, "sse": sse(f)} for f in frames],
    "unknown": {"about": "A frame type and a field a v1 client does not know: it ignores both.",
                "sse": 'event: typing\ndata: {"type":"typing","who":"agent"}\n\nevent: state\nid: c:9\ndata: {"type":"state","cursor":"c:9","seq":9,"state":{"seq":9,"working":true,"activity":null,"problem":null,"model":null,"effort":null,"waiting":null,"mood":"busy"}}\n\n',
                "expect": {"cursor": "c:9", "seq": 9, "messages": [], "replies": [],
                           "state": {"seq": 9, "working": True, "activity": None, "waiting": None}, "more_before": False}},
})

# --- connect-fresh
m1 = msg("m1", 1, "user", "Why is the build red?", 0)
s2 = state(2, True, "Reading the CI log")
m3 = msg("m3", 3, "assistant", "A test times out on the simulator.", 5)
write("connect-fresh.json", {
    "about": "No cursor: hello (resumed false), then a snapshot of the chat as it stands. Then a change arrives live.",
    "server": {
        "before": [ch("message", m1), ch("state", s2), ch("message", m3)],
        "connect": {"after": None},
        "during": [ch("state", state(4, False))],
        "frames": [{"type": "hello", "resumed": False},
                   {"type": "snapshot", "messages": [strip(m1), strip(m3)], "state": strip(s2), "replies": [], "more_before": False},
                   {"type": "state", "state": strip(state(4, False))}],
    },
    "client": {
        "start": None,
        "inputs": [{"source": "stream", "frame": hello(3, False)},
                   {"source": "stream", "frame": snap(3, [m1, m3], [], s2)},
                   {"source": "stream", "frame": f_state(state(4, False))}],
        "expect": expect(cur(4), 4, [m1, m3], [], state(4, False)),
    },
})

# --- reconnect-resume
m4 = msg("m4", 4, "assistant", "I raised the timeout to 30 s.", 8)
m5 = msg("m5", 5, "assistant", "CI is green.", 20)
write("reconnect-resume.json", {
    "about": "Reconnect with the cursor of change 2: hello (resumed true), the changes missed while away (3), then a live one (5). Nothing before the cursor comes again.",
    "server": {
        "before": [ch("message", m1), ch("state", s2), ch("message", m3)],
        "connect": {"after": "@2"},
        "during": [ch("message", m4)],
        "frames": [{"type": "hello", "resumed": True},
                   {"type": "message", "message": strip(m3)},
                   {"type": "message", "message": strip(m4)}],
    },
    "client": {
        "start": {"cursor": cur(2), "seq": 2, "messages": [m1], "replies": [], "state": s2, "more_before": False},
        "inputs": [{"source": "stream", "frame": hello(4, True)},
                   {"source": "stream", "frame": f_msg(m3)},
                   {"source": "stream", "frame": f_msg(m4)},
                   {"source": "stream", "frame": {"type": "ping"}},
                   {"source": "stream", "frame": f_msg(m5)}],
        "expect": expect(cur(5), 5, [m1, m3, m4, m5], [], s2),
    },
})

# --- cursor-expired
write("cursor-expired.json", {
    "about": "A cursor the host can no longer resume from (it forgot that far back, or the transcript was replaced): hello (resumed false), then a snapshot. Not a refusal.",
    "server": {
        "before": [ch("message", m1), ch("state", s2), ch("message", m3)],
        "expire": True,
        "connect": {"after": "@1"},
        "during": [],
        "frames": [{"type": "hello", "resumed": False},
                   {"type": "snapshot", "messages": [strip(m1), strip(m3)], "state": strip(s2), "replies": []}],
    },
    "client": {
        "start": {"cursor": cur(1), "seq": 1, "messages": [m1], "replies": [], "state": None, "more_before": False},
        "inputs": [{"source": "stream", "frame": hello(3, False)},
                   {"source": "stream", "frame": snap(3, [m1, m3], [], s2)}],
        "expect": expect(cur(3), 3, [m1, m3], [], s2),
    },
})

# --- duplicate
write("duplicate.json", {
    "about": "The same message arrives twice: on the stream, then in a read that overlapped it. The second does nothing.",
    "client": {
        "start": {"cursor": cur(3), "seq": 3, "messages": [m1, m3], "replies": [], "state": s2, "more_before": False},
        "inputs": [{"source": "stream", "frame": f_msg(m4)},
                   {"source": "read", "frame": f_msg(m4)},
                   {"source": "stream", "frame": f_msg(m4)}],
        "expect": expect(cur(4), 4, [m1, m3, m4], [], s2),
    },
})

# --- out-of-order
m4p = msg("m4", 4, "assistant", "I raised the time", 8, partial=True)
m4f = msg("m4", 6, "assistant", "I raised the timeout to 30 s.", 8)
s5 = state(5, True, "Pushing")
write("out-of-order.json", {
    "about": "A read that left before the stream moved on answers after it: its older version of m4 (seq 4) and older state (seq 5) must not replace the stream's newer m4 (seq 6), nor move the cursor back.",
    "client": {
        "start": {"cursor": cur(3), "seq": 3, "messages": [m1, m3], "replies": [], "state": s2, "more_before": False},
        "inputs": [{"source": "stream", "frame": f_msg(m4p)},
                   {"source": "stream", "frame": f_state(s5)},
                   {"source": "stream", "frame": f_msg(m4f)},
                   {"source": "read", "frame": f_msg(m4p)},
                   {"source": "read", "frame": f_state(s5)}],
        "expect": expect(cur(6), 6, [m1, m3, m4f], [], s5),
    },
})

# --- snapshot-reset
n1 = msg("n1", 2, "assistant", "A fresh session: the transcript was replaced.", 30)
write("snapshot-reset.json", {
    "about": "The host reset its history: a snapshot with a lower seq than the client holds still replaces everything, cursor and seq included. Frames after it apply from its seq.",
    "client": {
        "start": {"cursor": cur(6), "seq": 6, "messages": [m1, m3, m4f], "replies": [], "state": s5, "more_before": False},
        "inputs": [{"source": "stream", "frame": hello(2, False)},
                   {"source": "stream", "frame": {"type": "snapshot", "cursor": "e2:2", "seq": 2, "messages": [n1], "replies": [], "state": state(1, False), "more_before": False}},
                   {"source": "stream", "frame": {"type": "message", "cursor": "e2:3", "seq": 3, "message": msg("n2", 3, "assistant", "Still here.", 31)}}],
        "expect": expect("e2:3", 3, [n1, msg("n2", 3, "assistant", "Still here.", 31)], [], state(1, False)),
    },
})

# --- message-update
p1 = msg("m2", 2, "assistant", "Looking at", 3, partial=True)
p2 = msg("m2", 3, "assistant", "Looking at the CI log", 3, partial=True)
p3 = msg("m2", 4, "assistant", "Looking at the CI log now.", 3)
write("message-update.json", {
    "about": "A message written in parts (an Orca chat): versions with partial true, then the final one. Each replaces the last in place, by id.",
    "server": {
        "before": [ch("message", m1)],
        "connect": {"after": "@1"},
        "during": [ch("message", p1), ch("message", p2), ch("message", p3)],
        "frames": [{"type": "hello", "resumed": True},
                   {"type": "message", "message": strip(p1)},
                   {"type": "message", "message": strip(p2)},
                   {"type": "message", "message": strip(p3)}],
    },
    "client": {
        "start": {"cursor": cur(1), "seq": 1, "messages": [m1], "replies": [], "state": None, "more_before": False},
        "inputs": [{"source": "stream", "frame": f_msg(p1)},
                   {"source": "stream", "frame": f_msg(p2)},
                   {"source": "stream", "frame": f_msg(p3)}],
        "expect": expect(cur(4), 4, [m1, p3], [], None),
    },
})

# --- reply-lifecycle
ra = reply("rpl_7", 2, "pending", "Merge it.", 10)
rb = reply("rpl_7", 3, "queued", "Merge it.", 10)
rc = reply("rpl_7", 4, "delivering", "Merge it.", 10)
mm = msg("m9", 5, "user", "Merge it.", 12, reply_id="rpl_7")
rd = reply("rpl_7", 6, "delivered", "Merge it.", 10, message_id="m9")
write("reply-lifecycle.json", {
    "about": "A reply the person sent: pending, queued behind the agent's turn, delivering, then delivered. On delivery it becomes message m9, which names it by reply_id; the reply names m9 by message_id.",
    "server": {
        "before": [ch("message", m1)],
        "connect": {"after": "@1"},
        "during": [ch("reply", ra), ch("reply", rb), ch("reply", rc), ch("message", mm), ch("reply", rd)],
        "frames": [{"type": "hello", "resumed": True},
                   {"type": "reply", "reply": strip(ra)},
                   {"type": "reply", "reply": strip(rb)},
                   {"type": "reply", "reply": strip(rc)},
                   {"type": "message", "message": strip(mm)},
                   {"type": "reply", "reply": strip(rd)}],
    },
    "client": {
        "start": {"cursor": cur(1), "seq": 1, "messages": [m1], "replies": [], "state": None, "more_before": False},
        "inputs": [{"source": "stream", "frame": f_reply(ra)},
                   {"source": "stream", "frame": f_reply(rb)},
                   {"source": "read", "frame": f_reply(ra)},
                   {"source": "stream", "frame": f_reply(rc)},
                   {"source": "stream", "frame": f_msg(mm)},
                   {"source": "stream", "frame": f_reply(rd)}],
        "expect": expect(cur(6), 6, [m1, mm], [rd], None),
        "ticks": {"rpl_7": 2},
    },
})

# --- earlier
e = [msg("m%d" % i, i, "user" if i % 2 else "assistant", "Message %d" % i, i) for i in range(1, 6)]
write("earlier.json", {
    "about": "Load earlier: a read with before answers an earlier frame. Its messages go in front, each once; the cursor and seq do not move.",
    "client": {
        "start": {"cursor": cur(9), "seq": 9, "messages": e[3:], "replies": [], "state": None, "more_before": True},
        "inputs": [{"source": "read", "frame": {"type": "earlier", "messages": e[1:4], "more_before": True}}],
        "expect": expect(cur(9), 9, e[1:], [], None, True),
    },
})

# --- refusals
write("refusals.json", {
    "about": "Each refusal before a stream starts, each close code, and what the client does about it. `action` is one of: stop, reauth (new bearer, then once more), read (read every 2 s, stream again after retry_after_ms), backoff (read, reconnect with back-off), now (reconnect at once), after (reconnect after retry_after_ms, no back-off).",
    "http": [
        {"status": 400, "error": "bad_request", "action": "stop", "query": "v=1&after=c:1&before=m1"},
        {"status": 400, "error": "unsupported_version", "action": "stop", "query": "v=2"},
        {"status": 400, "error": "unsupported_version", "action": "stop", "query": ""},
        {"status": 401, "error": "unauthorized", "action": "reauth"},
        {"status": 403, "error": "forbidden", "action": "stop"},
        {"status": 404, "error": "not_found", "action": "stop"},
        {"status": 429, "error": "busy", "action": "read", "retry_after": 30},
        {"status": 500, "error": "internal", "action": "backoff"},
        {"status": 502, "error": "internal", "action": "backoff"},
    ],
    "close": [
        {"code": 4000, "reason": "rotate", "retry_after_ms": 0, "action": "now"},
        {"code": 4001, "reason": "unauthorized", "retry_after_ms": 0, "action": "reauth"},
        {"code": 4003, "reason": "forbidden", "retry_after_ms": 0, "action": "stop"},
        {"code": 4004, "reason": "gone", "retry_after_ms": 0, "action": "stop"},
        {"code": 4029, "reason": "busy", "retry_after_ms": 30000, "action": "read"},
        {"code": 4500, "reason": "internal", "retry_after_ms": 0, "action": "backoff"},
        {"code": 4503, "reason": "restarting", "retry_after_ms": 2000, "action": "after"},
    ],
    "dropped": {"about": "A stream that ends without a close frame, or a network error", "action": "backoff"},
    "backoff_ms": [500, 1000, 2000, 4000, 8000, 15000, 15000],
    "jitter": 0.2,
    "backoff_resets_after_ms": 10000,
    "read_interval_ms": 2000,
    "ping_interval_ms": 15000,
    "quiet_limit_ms": 40000,
    "rotate_after_ms": 600000,
})
print("ok")

# --- writes: what each write answers and the frames it produces
q = {"id": "q1", "question": "Merge now or wait for review?", "options": [{"id": "merge", "label": "Merge now"}, {"id": "wait", "label": "Wait for review"}], "multiple": False, "free_text": True}
w_state = state(2, False, None, waiting=q)
w1 = reply("rpl_8", 3, "queued", "Also bump the version.", 40)
w2 = reply("rpl_8", 4, "delivering", "Also bump the version.", 40)
w3 = reply("rpl_9", 5, "removed", "Never mind.", 41)
ans = reply("rpl_10", 6, "pending", "Merge now", 42, extra={"answers": "q1", "options": ["merge"]})
write("writes.json", {
    "about": "The four writes (docs/live-protocol.md#writes): the request, the answer, and the frames every open stream then gets. A repeat with the same client_ref answers the first reply and produces no frame.",
    "writes": [
        {"name": "send", "request": {"method": "POST", "path": "messages", "body": {"text": "Also bump the version.", "client_ref": "ref-rpl_8", "force": False, "images": []}},
         "status": 201, "answer": strip(w1), "frames": [{"type": "reply", "reply": strip(w1)}]},
        {"name": "send again", "request": {"method": "POST", "path": "messages", "body": {"text": "Also bump the version.", "client_ref": "ref-rpl_8", "force": False, "images": []}},
         "status": 200, "answer": strip(w1), "frames": []},
        {"name": "force", "request": {"method": "POST", "path": "replies/rpl_8/force", "body": None},
         "status": 200, "answer": strip(w2), "frames": [{"type": "reply", "reply": strip(w2)}]},
        {"name": "remove", "request": {"method": "DELETE", "path": "replies/rpl_9", "body": None},
         "status": 200, "answer": strip(w3), "frames": [{"type": "reply", "reply": strip(w3)}]},
        {"name": "answer", "request": {"method": "POST", "path": "answer", "body": {"question_id": "q1", "option_ids": ["merge"], "text": None, "client_ref": "ref-rpl_10"}},
         "status": 201, "answer": strip(ans), "frames": [{"type": "reply", "reply": strip(ans)}, {"type": "state", "state": strip(state(7, False, None))}]},
    ],
    "refusals": [
        {"name": "force a reply that is not queued", "status": 409, "error": "conflict"},
        {"name": "remove a reply already delivering or delivered", "status": 409, "error": "conflict"},
        {"name": "answer a question that is not open", "status": 409, "error": "conflict"},
        {"name": "send with no text and no images", "status": 400, "error": "bad_request"},
    ],
    "client": {
        "about": "The client forces a send while the chat waits on the person: the question would otherwise hold the reply in the queue for good.",
        "start": {"cursor": cur(2), "seq": 2, "messages": [], "replies": [], "state": w_state, "more_before": False},
        "send": {"text": "Also bump the version."},
        "expect_force": True,
    },
})
print("writes ok")

# --- display-order
u = msg("u2", 3, "user", "Also check the iPad.", 10)
a = msg("a2", 4, "assistant", "The iPhone run is green.", 8)
n = msg("t9", 5, "tool", "xcodebuild test", None) if False else dict(msg("t9", 5, "tool", "xcodebuild test", 0, tool="Bash"), at=None)
write("display-order.json", {
    "about": "Messages show in order of `at`, not of arrival: the agent's a2 (written at :08) arrives after the person's u2 (:10), and goes before it. A message without `at` (t9) stays where it arrived: it sorts at the `at` of the message before it. Equal `at` keeps the order taken.",
    "client": {
        "start": {"cursor": cur(2), "seq": 2, "messages": [m1], "replies": [], "state": None, "more_before": False},
        "inputs": [{"source": "stream", "frame": f_msg(u)},
                   {"source": "stream", "frame": f_msg(a)},
                   {"source": "stream", "frame": f_msg(n)}],
        "expect": expect(cur(5), 5, [m1, a, u, n], [], None),
    },
})
print("order ok")
