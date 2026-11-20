> ## Documentation Index
> Fetch the complete documentation index at: https://agentclientprotocol.com/llms.txt
> Use this file to discover all available pages before exploring further.

# Overview

> How the Agent Client Protocol works

The Agent Client Protocol allows [Agents](#agent) and [Clients](#client) to communicate by exposing methods that each side can call and sending notifications to inform each other of events.

## Communication Model

The protocol follows the [JSON-RPC 2.0](https://www.jsonrpc.org/specification) specification with two types of messages:

* **Methods**: Request-response pairs that expect a result or error
* **Notifications**: One-way messages that don't expect a response

## Message Flow

A typical flow follows this pattern:

**1. Initialization Phase**

* Client → Agent: `initialize` to establish connection
* Client: completes an advertised authentication flow if required; for example,
  `authenticate` for an Agent-handled method or launch and reconnect for a
  terminal method

**2. Session Setup - either:**

* Client → Agent: `session/new` to create a new session
* Client → Agent: `session/load` to resume an existing session if supported

**3. Prompt Turn**

* Client → Agent: `session/prompt` to send user message
* Agent → Client: `session/update` notifications for progress updates and user-facing notices
* Agent → Client: File operations or permission requests as needed
* Client → Agent: `session/cancel` to interrupt processing if needed
* Turn ends and the Agent sends the `session/prompt` response with a stop reason

## Agent

Agents are programs that use generative AI to autonomously modify code. They typically run as subprocesses of the Client.

### Baseline Methods

**initialize**

[Negotiate versions and exchange capabilities.](https://agentclientprotocol.com/protocol/v1/initialization.md).

**authenticate**

Authenticate with the Agent (if required).

**session/new**

[Create a new conversation
session](https://agentclientprotocol.com/protocol/v1/session-setup.md#creating-a-session).

**session/prompt**

[Send user prompts](https://agentclientprotocol.com/protocol/v1/prompt-turn.md#1-user-message) to the Agent.

### Optional Methods

**session/load**

[Load an existing session](https://agentclientprotocol.com/protocol/v1/session-setup.md#loading-sessions)
(requires `loadSession` capability).

**logout**

[End the current authenticated state](https://agentclientprotocol.com/protocol/v1/authentication.md#logging-out)
(requires `agentCapabilities.auth.logout` capability).

**session/set\_mode**

[Switch between agent operating
modes](https://agentclientprotocol.com/protocol/v1/session-modes.md#setting-the-current-mode).

### Notifications

**session/cancel**

[Cancel ongoing operations](https://agentclientprotocol.com/protocol/v1/prompt-turn.md#cancellation) (no
response expected).

## Client

Clients provide the interface between users and agents. They are typically code editors (IDEs, text editors) but can also be other UIs for interacting with agents. Clients manage the environment, handle user interactions, and control access to resources.

### Baseline Methods

**session/request\_permission**

[Request user authorization](https://agentclientprotocol.com/protocol/v1/tool-calls.md#requesting-permission)
for tool calls.

### Optional Methods

**fs/read\_text\_file**

[Read file contents](https://agentclientprotocol.com/protocol/v1/file-system.md#reading-files) (requires
`fs.readTextFile` capability).

**fs/write\_text\_file**

[Write file contents](https://agentclientprotocol.com/protocol/v1/file-system.md#writing-files) (requires
`fs.writeTextFile` capability).

**terminal/create**

[Create a new terminal](https://agentclientprotocol.com/protocol/v1/terminals.md) (requires `terminal`
capability).

**terminal/output**

Get terminal output and exit status (requires `terminal` capability).

**terminal/release**

Release a terminal (requires `terminal` capability).

**terminal/wait\_for\_exit**

Wait for terminal command to exit (requires `terminal` capability).

**terminal/kill**

Kill terminal command without releasing (requires `terminal` capability).

**elicitation/create**

[Request structured information from the user](https://agentclientprotocol.com/protocol/v1/elicitation.md)
(requires the matching `elicitation` mode capability).

### Notifications

**elicitation/complete**

[Report completion of an out-of-band URL
interaction](https://agentclientprotocol.com/protocol/v1/elicitation.md#url-completion) (no response expected).

**session/update**

[Send session updates](https://agentclientprotocol.com/protocol/v1/prompt-turn.md#3-agent-reports-output) to
inform the Client of changes (no response expected). This includes:

* [Message chunks](https://agentclientprotocol.com/protocol/v1/content.md) (agent, user, thought)
* [Tool calls and updates](https://agentclientprotocol.com/protocol/v1/tool-calls.md)
* [Plans](https://agentclientprotocol.com/protocol/v1/agent-plan.md)
* [Available commands updates](https://agentclientprotocol.com/protocol/v1/slash-commands.md#advertising-commands)
* [Mode changes](https://agentclientprotocol.com/protocol/v1/session-modes.md#from-the-agent)
* [User-facing notices](https://agentclientprotocol.com/protocol/v1/prompt-turn.md#session-notices)
* [Context compactions](https://agentclientprotocol.com/protocol/v1/prompt-turn.md#session-compaction)

## Argument requirements

* All file paths in the protocol **MUST** be absolute.
* Line numbers are 1-based

## Error Handling

All methods follow standard JSON-RPC 2.0 [error handling](https://www.jsonrpc.org/specification#error_object):

* Successful responses include a `result` field
* Errors include an `error` object with `code` and `message`
* Notifications never receive responses (success or error)

See [Errors](https://agentclientprotocol.com/protocol/v1/error.md) for the error codes ACP uses and when to use them.

## Conventions

Unless explicitly defined otherwise in the schema, ACP-defined JSON object property keys use `camelCase`. String values carried by discriminator fields use `snake_case`. The JSON-RPC envelope fields (`jsonrpc`, `id`, `method`, `params`, `result`, and `error`) follow the JSON-RPC 2.0 specification.

## Extensibility

The protocol provides built-in mechanisms for adding custom functionality while maintaining compatibility:

* Add custom data using `_meta` fields
* Create custom methods by prefixing their name with underscore (`_`)
* Advertise custom capabilities during initialization

Learn about [protocol extensibility](https://agentclientprotocol.com/protocol/v1/extensibility.md) to understand how to use these mechanisms.

## Next Steps

* Read the [Security Considerations](https://agentclientprotocol.com/protocol/v1/security.md) before shipping an Agent or Client
* Learn about [Initialization](https://agentclientprotocol.com/protocol/v1/initialization.md) to understand version and capability negotiation
* Understand [Session Setup](https://agentclientprotocol.com/protocol/v1/session-setup.md) for creating and loading sessions
* Review the [Prompt Turn](https://agentclientprotocol.com/protocol/v1/prompt-turn.md) lifecycle
* Explore [Extensibility](https://agentclientprotocol.com/protocol/v1/extensibility.md) to add custom features
* Check your agent implementation with the [Test Compatibility Kit](https://agentclientprotocol.com/libraries/testing.md)


This documentation is built and hosted on [Mintlify](https://mintlify.com), a developer documentation platform.