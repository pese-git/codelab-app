Last revised: 2026-11-20

# CodeLab Privacy Policy

Draft pending legal review. Русская редакция: [`PRIVACY.ru.md`](PRIVACY.ru.md). Terms of use: [`TERMS.md`](TERMS.md).

This policy covers the CodeLab desktop app (`codelab_desktop`), the terminal client `codelab` and the Dart agent `codelab-agent`. CodeLab runs on your computer. It has no accounts and no server of its own.

## 1. No telemetry

CodeLab does not send usage analytics, crash reports or an installation identifier. It contains no analytics SDK. The project does not receive any data about how you use the software.

## 2. Network requests

This list describes the build you are reading about, not a plan. Each row is an outgoing connection that the code can open, who starts it and what it carries.

| Where | When | What is sent | How to avoid it |
|---|---|---|---|
| The model provider you configured (an OpenAI-compatible or Anthropic API address) | Every agent turn | Your prompt, the session history, the contents of files and the output of commands the agent has read, and your API key in the authorization header | Do not configure a provider, or use a local model |
| The same provider address | When you set up or re-check a provider | A `GET` request for the model list (`/models`, or `/v1/models` for Anthropic) with your API key in the authorization header. Redirects are not followed, so the key does not go to another host | Skip the check |
| MCP servers from your configuration | When the agent calls a tool of that server | The arguments of the call | Remove the server from the configuration |
| An external ACP agent that you connect yourself | While the connection is open | Everything the client and the agent exchange over ACP: your messages, files the agent asks to read, command output. Over a local `stdio:` profile the data goes to a process on your computer; over a `ws://` or `wss://` profile it goes to the address you gave, with the headers you set | Use the built-in agent |

Commands you run yourself and tools you approve for the agent run programs that may use the network. Those requests belong to those programs, and CodeLab does not list them. Links you choose to open (for example release notes) are opened by your browser, not by CodeLab.

There are no other outgoing requests in this build: no update check and no web tools. If a later version adds one, this section is changed in the same release.

## 3. What is stored on this computer

- The configuration folder (`$CODELAB_HOME`, by default `~/.codelab`): the configuration file, session logs and agent logs. Session logs hold your prompts and the agent's answers.
- API keys: read from environment variables or, if you choose that backend, written as plain text to a file in the configuration folder with access limited to your user. See the [configuration guide](docs/user/configuration.md).
- The desktop app also keeps its own settings, such as the interface language and recent projects, in the operating system's per-user preferences.

Nothing from this list is sent anywhere except as described in section 2. Do not publish logs before you have looked through them: they can contain keys or personal data from a conversation.

## 4. Third-party policies

Data sent to a model provider, an MCP server or an external ACP agent is handled under that service's own policy. CodeLab does not control it and is not a party to it. Read those policies before you connect a service. See also [`TERMS.md`](TERMS.md), section 3.

## 5. Contact and changes

Questions: `<contact>`. Project site: `<site>`.

The date in the first line is the date of this revision. A new revision changes that date and is listed in the "Privacy" part of [`CHANGELOG.md`](CHANGELOG.md). The license is in [`LICENSE`](LICENSE); components under their own licenses are in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
