#!/usr/bin/env python3
"""Stand-in for the Claude, ChatGPT and Gemini APIs, for checking Tether's assistant offline.

It speaks each service's streaming format well enough to drive a full turn: a first reply
that calls one of Tether's tools, then a final reply once the tool result comes back.
It also refuses a follow-up request that does not replay the model's own hidden state
(thinking block, reasoning item, thought signature), which is the mistake most likely to
break a real tool loop.

    Scripts/mock-ai.py 8765 /tmp/requests.jsonl      # port, optional request log

Used by `TETHER_SCENE=aitest` (see CLAUDE.md). No real service is contacted.
"""
import json
import re
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
LOG = sys.argv[2] if len(sys.argv) > 2 else None


def first_node_id(system):
    match = re.search(r"- \[([0-9a-f]{8})\]", system or "")
    return match.group(1) if match else "missing"


def facts(system, history_text):
    """What a model can see: used to prove the three services share one context."""
    seen = []
    if "[Claude" in history_text:
        seen.append("claude-reply")
    if "[ChatGPT" in history_text:
        seen.append("chatgpt-reply")
    if "short summaries" in (system or ""):
        seen.append("shared-memory")
    return ",".join(seen) or "nothing"


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def _json(self, status, payload):
        data = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _sse(self, events):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Connection", "close")
        self.end_headers()
        for name, payload in events:
            if name:
                self.wfile.write(f"event: {name}\n".encode())
            self.wfile.write(f"data: {json.dumps(payload)}\n\n".encode())
            self.wfile.flush()
        self.close_connection = True

    def do_GET(self):
        if self.path.startswith("/v1beta/models"):
            return self._json(200, {"models": [
                {"name": "models/gemini-mock-pro", "displayName": "Gemini Mock Pro", "supportedGenerationMethods": ["generateContent"]},
                {"name": "models/embedding-mock", "displayName": "Embedding", "supportedGenerationMethods": ["embedContent"]},
            ]})
        if self.path.startswith("/v1/models"):
            if self.headers.get("x-api-key"):
                return self._json(200, {"data": [
                    {"id": "claude-opus-5-5", "display_name": "Claude Opus 5.5", "max_tokens": 128000},
                    {"id": "claude-haiku-5-5", "display_name": "Claude Haiku 5.5", "max_tokens": 128000},
                ], "has_more": False})
            return self._json(200, {"data": [
                {"id": "gpt-mock", "created": 2}, {"id": "gpt-mock-mini", "created": 1},
                {"id": "text-embedding-mock", "created": 3},
            ]})
        self._json(404, {"error": {"message": "not found"}})

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = json.loads(self.rfile.read(length) or b"{}")
        if LOG:
            with open(LOG, "a") as handle:
                handle.write(json.dumps({"path": self.path, "headers": {k.lower(): v for k, v in self.headers.items()}, "body": body}) + "\n")
        if self.path == "/v1/messages":
            return self.claude(body)
        if self.path == "/v1/responses":
            return self.openai(body)
        if ":streamGenerateContent" in self.path:
            return self.gemini(body)
        self._json(404, {"error": {"message": "not found"}})

    # --- Claude: Messages API -------------------------------------------------------------

    def claude(self, body):
        if not self.headers.get("x-api-key"):
            return self._json(401, {"type": "error", "error": {"type": "authentication_error", "message": "invalid x-api-key"}})
        messages = body.get("messages", [])
        last = messages[-1]["content"] if messages else ""
        history = json.dumps(messages)
        start = ("message_start", {"type": "message_start", "message": {"id": "msg_mock", "model": body.get("model"), "content": []}})
        if isinstance(last, list) and any(block.get("type") == "tool_result" for block in last):
            previous = messages[-2]["content"]
            types = [block.get("type") for block in previous]
            if "thinking" not in types or previous[types.index("thinking")].get("signature") != "sig-claude":
                return self._json(400, {"type": "error", "error": {"type": "invalid_request_error", "message": "thinking block was not replayed unchanged"}})
            declined = any(block.get("is_error") for block in last)
            text = "I left the node as it is." if declined else "Done — I added the line to the plan."
            return self._sse([start,
                ("content_block_start", {"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}}),
                ("content_block_delta", {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": text[:10]}}),
                ("content_block_delta", {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": text[10:]}}),
                ("content_block_stop", {"type": "content_block_stop", "index": 0}),
                ("message_delta", {"type": "message_delta", "delta": {"stop_reason": "end_turn"}, "usage": {"output_tokens": 9}}),
                ("message_stop", {"type": "message_stop"})])
        arguments = json.dumps({"node": first_node_id(body.get("system")), "text": "## From Claude\nAdded by the **Claude** mock."})
        cut = len(arguments) // 2
        self._sse([start,
            ("content_block_start", {"type": "content_block_start", "index": 0, "content_block": {"type": "thinking", "thinking": "", "signature": ""}}),
            ("content_block_delta", {"type": "content_block_delta", "index": 0, "delta": {"type": "signature_delta", "signature": "sig-claude"}}),
            ("content_block_stop", {"type": "content_block_stop", "index": 0}),
            ("content_block_start", {"type": "content_block_start", "index": 1, "content_block": {"type": "text", "text": ""}}),
            ("content_block_delta", {"type": "content_block_delta", "index": 1, "delta": {"type": "text_delta", "text": "I'll add that to the plan."}}),
            ("content_block_stop", {"type": "content_block_stop", "index": 1}),
            ("content_block_start", {"type": "content_block_start", "index": 2, "content_block": {"type": "tool_use", "id": "toolu_mock", "name": "append_to_node", "input": {}}}),
            ("content_block_delta", {"type": "content_block_delta", "index": 2, "delta": {"type": "input_json_delta", "partial_json": arguments[:cut]}}),
            ("content_block_delta", {"type": "content_block_delta", "index": 2, "delta": {"type": "input_json_delta", "partial_json": arguments[cut:]}}),
            ("content_block_stop", {"type": "content_block_stop", "index": 2}),
            ("message_delta", {"type": "message_delta", "delta": {"stop_reason": "tool_use"}, "usage": {"output_tokens": 30}}),
            ("message_stop", {"type": "message_stop"})])

    # --- ChatGPT: Responses API -----------------------------------------------------------

    def openai(self, body):
        if not self.headers.get("Authorization", "").startswith("Bearer "):
            return self._json(401, {"error": {"message": "Incorrect API key provided"}})
        items = body.get("input", [])
        history = json.dumps([item for item in items if item.get("role")])
        outputs = [item for item in items if item.get("type") == "function_call_output"]
        if outputs:
            kinds = [item.get("type") for item in items]
            if "reasoning" not in kinds or "function_call" not in kinds or kinds.index("reasoning") > kinds.index("function_call_output"):
                return self._json(400, {"error": {"message": "reasoning item was not passed back with the tool output"}})
            text = "Saved. I can see: " + facts(body.get("instructions"), history)
            message = {"id": "msg_1", "type": "message", "role": "assistant", "content": [{"type": "output_text", "text": text}]}
            return self._sse([
                ("response.output_text.delta", {"type": "response.output_text.delta", "output_index": 0, "delta": text[:8]}),
                ("response.output_text.delta", {"type": "response.output_text.delta", "output_index": 0, "delta": text[8:]}),
                ("response.output_item.done", {"type": "response.output_item.done", "output_index": 0, "item": message}),
                ("response.completed", {"type": "response.completed", "response": {"status": "completed", "output": [message]}})])
        reasoning = {"id": "rs_1", "type": "reasoning", "summary": []}
        arguments = json.dumps({"text": "The user prefers short summaries."})
        call = {"id": "fc_1", "type": "function_call", "call_id": "call_mock", "name": "remember", "arguments": arguments, "status": "completed"}
        self._sse([
            ("response.output_item.done", {"type": "response.output_item.done", "output_index": 0, "item": reasoning}),
            ("response.output_item.added", {"type": "response.output_item.added", "output_index": 1, "item": dict(call, arguments="")}),
            ("response.function_call_arguments.delta", {"type": "response.function_call_arguments.delta", "output_index": 1, "delta": arguments[:12]}),
            ("response.function_call_arguments.delta", {"type": "response.function_call_arguments.delta", "output_index": 1, "delta": arguments[12:]}),
            ("response.output_item.done", {"type": "response.output_item.done", "output_index": 1, "item": call}),
            ("response.completed", {"type": "response.completed", "response": {"status": "completed", "output": [reasoning, call]}})])

    # --- Gemini: generateContent ----------------------------------------------------------

    def gemini(self, body):
        if not self.headers.get("x-goog-api-key"):
            return self._json(400, {"error": {"code": 400, "message": "API key not valid", "status": "INVALID_ARGUMENT"}})
        contents = body.get("contents", [])
        system = "".join(part.get("text", "") for part in body.get("systemInstruction", {}).get("parts", []))
        history = json.dumps([c for c in contents if all("text" in p for p in c.get("parts", []))])
        answered = contents and any("functionResponse" in part for part in contents[-1].get("parts", []))
        if answered:
            calls = [part for part in contents[-2].get("parts", []) if "functionCall" in part]
            if not calls or calls[0].get("thoughtSignature") != "sig-gemini":
                return self._json(400, {"error": {"code": 400, "message": "Function call is missing a thought_signature", "status": "INVALID_ARGUMENT"}})
            result = json.dumps(contents[-1]["parts"][0]["functionResponse"].get("response", {}))
            text = "I read the node (%d chars). I can see: %s" % (len(result), facts(system, history))
            return self._sse([
                (None, {"candidates": [{"content": {"role": "model", "parts": [{"text": text[:12]}]}}]}),
                (None, {"candidates": [{"content": {"role": "model", "parts": [{"text": text[12:]}]}, "finishReason": "STOP"}]})])
        self._sse([
            (None, {"candidates": [{"content": {"role": "model", "parts": [{"text": "hidden", "thought": True}]}}]}),
            (None, {"candidates": [{"content": {"role": "model", "parts": [
                {"functionCall": {"name": "read_node", "args": {"node": first_node_id(system)}}, "thoughtSignature": "sig-gemini"}]},
                "finishReason": "STOP"}]})])


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
