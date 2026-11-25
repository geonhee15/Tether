#!/usr/bin/env python3
"""A tiny MCP server over stdio, for checking Tether's MCP client (`TETHER_SCENE=mcptest`).

It offers two tools: `echo` (marked read-only) and `add`. Nothing leaves this process.
"""
import json
import sys

TOOLS = [
    {"name": "echo", "description": "Returns the text it is given.",
     "inputSchema": {"type": "object", "properties": {"text": {"type": "string"}}, "required": ["text"]},
     "annotations": {"readOnlyHint": True}},
    {"name": "add", "description": "Adds two numbers.",
     "inputSchema": {"type": "object", "properties": {"a": {"type": "number"}, "b": {"type": "number"}}, "required": ["a", "b"]}},
]


def reply(identifier, result=None, error=None):
    message = {"jsonrpc": "2.0", "id": identifier}
    if error:
        message["error"] = {"code": -32000, "message": error}
    else:
        message["result"] = result
    sys.stdout.write(json.dumps(message) + "\n")
    sys.stdout.flush()


for line in sys.stdin:
    try:
        request = json.loads(line)
    except ValueError:
        continue
    method, identifier, params = request.get("method"), request.get("id"), request.get("params") or {}
    if identifier is None:
        continue  # a notification
    if method == "initialize":
        reply(identifier, {"protocolVersion": params.get("protocolVersion", "2025-06-18"), "capabilities": {"tools": {}},
                           "serverInfo": {"name": "mock", "version": "1"}})
    elif method == "tools/list":
        reply(identifier, {"tools": TOOLS})
    elif method == "tools/call":
        name, arguments = params.get("name"), params.get("arguments") or {}
        if name == "echo":
            reply(identifier, {"content": [{"type": "text", "text": "echo: " + str(arguments.get("text", ""))}]})
        elif name == "add":
            reply(identifier, {"content": [{"type": "text", "text": str(arguments.get("a", 0) + arguments.get("b", 0))}]})
        else:
            reply(identifier, {"content": [{"type": "text", "text": "no such tool"}], "isError": True})
    else:
        reply(identifier, error="unknown method " + str(method))
