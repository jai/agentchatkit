import AgentChatLive
import Foundation

// The host's answers to the client's requests: resume, prompt, edit and remove, and the answer to its question.
extension LiveLoopbackServer {
    func handle(_ message: JSONValue, from name: String) async {
        let id = message["id"] ?? .null
        let params = message["params"] ?? .null
        switch message["method"]?.string {
        case "session/resume":
            resume(params, id: id, on: name)
        case "session/prompt":
            await prompt(params, id: id, on: name)
        case "_agentchatkit/edit", "_agentchatkit/remove":
            await change(message["method"]?.string ?? "", params, id: id, on: name)
        default:
            send(Self.error(id, AcpError.methodNotFound, "method not found"), to: name)
        }
    }

    func change(_ method: String, _ params: JSONValue, id: JSONValue, on name: String) async {
        guard let target = params["messageId"]?.string,
              var ours = current[target]?.at("_meta", "agentchatkit")?.object,
              ["pending", "queued", "failed"].contains(ours["status"]?.string ?? "") else {
            return send(Self.error(id, AcpError.conflict, "conflict"), to: name)
        }
        let forced = params["force"] == .bool(true)
        var update: [String: JSONValue] = ["sessionUpdate": "user_message", "messageId": .string(target)]
        if method == "_agentchatkit/remove" {
            ours["status"] = "removed"
        } else {
            if let prompt = params["prompt"] {
                update["content"] = prompt
            }
            if forced {
                ours["status"] = "pending"
            }
        }
        update["_meta"] = ["agentchatkit": .object(ours)]
        publish(.object(update))
        send(Self.result(id, ["messageId": .string(target)]), to: name)
        if forced, let text = current[target]?["content"]?.array?.first?["text"]?.string {
            await prompted?(target, text, true)
        }
    }

    func resume(_ params: JSONValue, id: JSONValue, on name: String) {
        let replay = params["replayFrom"]
        if replay?["type"]?.string == "_cursor" {
            guard let cursor = replay?["cursor"]?.string, cursor.hasPrefix("c:"),
                  let after = Int(cursor.dropFirst(2)), after <= seq, after >= forgottenBefore else {
                return send(Self.error(id, AcpError.invalidParams, "cursor expired"), to: name)
            }
            for entry in log where entry.seq > after && entry.update["sessionUpdate"]?.string != "state_update" {
                send(Self.note(entry.update, cursor: entry.seq, session: session), to: name)
            }
        } else {
            for message in order.suffix(200).compactMap({ current[$0] }) {
                send(Self.note(message, cursor: seq, session: session), to: name)
            }
        }
        send(Self.note(state, cursor: seq, session: session), to: name)
        if let question {
            send(Self.questionMessage(question.id, question.params), to: name)
        }
        send(Self.result(id, [:]), to: name)
    }

    func prompt(_ params: JSONValue, id: JSONValue, on name: String) async {
        let ours = params.at("_meta", "agentchatkit")
        let clientRef = ours?["clientRef"]?.string
        if let clientRef, let first = order.first(where: {
            current[$0]?.at("_meta", "agentchatkit", "clientRef")?.string == clientRef
        }) {
            return send(Self.result(id, ["messageId": .string(first)]), to: name)
        }
        let blocks = params["prompt"]?.array ?? []
        let text = blocks.compactMap { $0["text"]?.string }.joined(separator: "\n\n")
        guard !blocks.isEmpty else {
            return send(Self.error(id, AcpError.invalidParams, "nothing to send"), to: name)
        }
        let force = ours?["force"] == .bool(true)
        userMessages += 1
        let messageID = "u\(userMessages)"
        let images = blocks.filter { $0["type"]?.string == "image" }.indices.map { index -> JSONValue in
            ["type": "resource_link", "name": .string("screenshot-\(index + 1).jpg"),
             "uri": .string("attachments/\(messageID)/\(index)"), "mimeType": "image/jpeg", ]
        }
        let words: [JSONValue] = text.isEmpty ? [] : [["type": "text", "text": .string(text)]]
        publish([
            "sessionUpdate": "user_message", "messageId": .string(messageID), "content": .array(words + images),
            "_meta": ["agentchatkit": [
                "at": .string(LiveDates.string(.now)), "sender": ["login": "jai", "name": "Jai"],
                "status": phase == .running && !force ? "queued" : "pending", "clientRef": JSONValue(clientRef),
            ], ],
        ])
        send(Self.result(id, ["messageId": .string(messageID)]), to: name)
        await prompted?(messageID, text, force)
    }

    func take(answer message: JSONValue, from name: String) async {
        guard let open = question, message["id"] == open.id else {
            return
        }
        question = nil
        cancelQuestion(open.id, except: name)
        guard message.at("result", "action")?.string == "accept" else {
            setState(.running)
            return
        }
        let content = message.at("result", "content")
        let chosen = content?["choices"]?.array?.compactMap(\.string) ?? [content?["choice"]?.string].compactMap(\.self)
        let words = content?["text"]?.string
        let properties = open.params.at("requestedSchema", "properties")
        let schema = properties?["choice"] ?? properties?.at("choices", "items")
        let ids = schema?["enum"]?.array?.compactMap(\.string) ?? []
        let names = schema?["enumNames"]?.array?.compactMap(\.string) ?? []
        let shown = chosen.map { id in ids.firstIndex(of: id).map { $0 < names.count ? names[$0] : id } ?? id }
        let text = [shown.joined(separator: ", "), words ?? ""].filter { !$0.isEmpty }.joined(separator: ": ")
        userMessages += 1
        publish([
            "sessionUpdate": "user_message", "messageId": .string("u\(userMessages)"),
            "content": [["type": "text", "text": .string(text)]],
            "_meta": ["agentchatkit": [
                "at": .string(LiveDates.string(.now)), "sender": ["login": "jai", "name": "Jai"], "status": "delivered",
            ], ],
        ])
        setState(.running)
        await answered?(chosen, words)
    }

    func cancelQuestion(_ id: JSONValue, except name: String) {
        for other in connections.keys where other != name {
            send(["jsonrpc": "2.0", "method": "$/cancel_request", "params": ["requestId": id]], to: other)
        }
    }
}
