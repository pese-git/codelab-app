> ## Documentation Index
> Fetch the complete documentation index at: https://agentclientprotocol.com/llms.txt
> Use this file to discover all available pages before exploring further.

# Architecture

> Overview of the Agent Client Protocol architecture.

The Agent Client Protocol defines a standard interface for communication between AI agents and client applications. The architecture is designed to be flexible, extensible, and platform-agnostic.

## Design Philosophy

The protocol architecture follows several key principles:

1. **MCP-friendly**: The protocol is built on JSON-RPC, and re-uses MCP types where possible so that integrators don't need to build yet-another representation for common data types.
2. **UX-first**: It is designed to solve the UX challenges of interacting with AI agents; ensuring there's enough flexibility to render clearly the agents intent, but is no more abstract than it needs to be.
3. **Trusted**: ACP works when you're using a code editor to talk to a model you trust. You still have controls over the agent's tool calls, but the code editor gives the agent access to local files and MCP servers.

## Setup

When the user tries to connect to an agent, the editor boots the agent sub-process on demand, and all communication happens over stdin/stdout.

Each connection can support several concurrent sessions, so you can have multiple trains of thought going on at once.

![Server Client setup](https://mintcdn.com/zed-685ed6d6/ZwvtxaoaZwBJrK5s/images/server-client.svg?fit=max\&auto=format\&n=ZwvtxaoaZwBJrK5s\&q=85\&s=336b604262b9b61ece9fc402774185bf)

ACP makes heavy use of JSON-RPC notifications to allow the agent to stream updates to the UI in real-time. It also uses JSON-RPC's bidirectional requests to allow the agent to make requests of the code editor: for example to request permissions for a tool call.

## MCP

Commonly the code editor will have user-configured MCP servers. When forwarding the prompt from the user, it passes configuration for these to the agent. This allows the agent to connect directly to the MCP server.

![MCP Server connection](https://mintcdn.com/zed-685ed6d6/ZwvtxaoaZwBJrK5s/images/mcp.svg?fit=max\&auto=format\&n=ZwvtxaoaZwBJrK5s\&q=85\&s=87650126080bf3bb4d983f447889ab86)

The code editor may itself also wish to export MCP based tools. Instead of trying to run MCP and ACP on the same socket, the code editor can provide its own MCP server as configuration. As agents may only support MCP over stdio, the code editor can provide a small proxy that tunnels requests back to itself:

![MCP connection to self](https://mintcdn.com/zed-685ed6d6/ZwvtxaoaZwBJrK5s/images/mcp-proxy.svg?fit=max\&auto=format\&n=ZwvtxaoaZwBJrK5s\&q=85\&s=dd128411c4be5945e131596190b41cb8)


This documentation is built and hosted on [Mintlify](https://mintlify.com), a developer documentation platform.