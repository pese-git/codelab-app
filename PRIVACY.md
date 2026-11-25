Last revised: 2026-11-25

# CodeLab Privacy Policy

Draft pending legal review. Русская редакция: [`PRIVACY.ru.md`](PRIVACY.ru.md). Terms of use: [`TERMS.md`](TERMS.md).

This policy covers the CodeLab app (`codelab_desktop`) on every platform and in every store where it is distributed, the terminal client `codelab` and the Dart agent `codelab-agent`. It is published by `<developer name>` ("the author"). CodeLab runs on your computer. It has no accounts, no sign-in and no server of its own. Through the software, the author does not collect, receive, store, sell or share your personal data; the only exception is reports that you choose to share through an app store (section 10).

## 1. No telemetry

CodeLab does not send usage analytics, crash reports or an installation identifier. It contains no analytics SDK. The project does not receive any data about how you use the software.

## 2. Network requests

This list describes the build you are reading about, not a plan. Each row is an outgoing connection that the code can open, who starts it and what it carries.

| Where | When | What is sent | How to avoid it |
|---|---|---|---|
| The model provider you configured (an OpenAI-compatible or Anthropic API address) | Every agent turn | Your prompt, the session history, the contents of files and the output of commands the agent has read, and your API key in the authorization header | Do not configure a provider, or use a local model |
| The same provider address | When you set up or re-check a provider | A `GET` request for the model list (`/models`, or `/v1/models` for Anthropic) with your API key in the authorization header. Redirects are not followed, so the key does not go to another host | Skip the check |
| MCP servers from your configuration | When a session is created or loaded (connection, `initialize`, `tools/list`), on every tool call, and again when reconnecting after a failure | Client information, the request for the tool list, the headers from your configuration (including tokens) and the arguments of the calls. A `stdio` server is a local process on your computer, and the data goes to it | Remove the server from the configuration |
| The host of an image from an agent answer | Only when you press "Show image" | A `GET` request to the image address, without keys or cookies, with the HTTP client's `User-Agent`. The host sees your IP address and the time of the request. The model or the agent chooses the address, and it can carry data. Only `https` is loaded, at most 3 redirects (each must be `https` too), a body of at most 32 MiB | Do not press "Show image" |
| An external ACP agent that you connect yourself | While the connection is open | Everything the client and the agent exchange over ACP: your messages, files the agent asks to read, command output. Over a local `stdio:` profile the data goes to a process on your computer; over a `ws://` or `wss://` profile it goes to the address you gave, with the headers you set | Use the built-in agent |

Commands you run yourself and tools you approve for the agent run programs that may use the network. Those requests belong to those programs, and CodeLab does not list them. Links you choose to open (for example release notes) are opened by your browser, not by CodeLab.

There are no other outgoing requests in this build: no update check and no web tools. If a later version adds one, this section is changed in the same release.

## 3. What is stored on this computer

- The configuration folder (`$CODELAB_HOME`, by default `~/.codelab`): the configuration file, session logs and agent logs. Session logs hold your prompts and the agent's answers.
- The desktop app's own logs: the `logs` folder in the application support folder of the operating system (the "Open log folder" button opens it).
- API keys: read from environment variables or, if you choose that backend, written as plain text to a file in the configuration folder with access limited to your user. See the [configuration guide](docs/user/configuration.md).
- The desktop app also keeps its own settings, such as the interface language and recent projects, in the operating system's per-user preferences.

Nothing from this list is sent anywhere except as described in section 2. Do not publish logs, including the app's own, before you have looked through them: they can contain keys or personal data from a conversation.

## 4. Third-party policies

Data sent to a model provider, an MCP server or an external ACP agent is handled under that service's own policy. CodeLab does not control it and is not a party to it. Read those policies before you connect a service. See also [`TERMS.md`](TERMS.md), section 3.

## 5. Contact and changes

Questions: `<contact>`. Project site: `<site>`.

The date in the first line is the date of this revision. A new revision changes that date and is listed in the release section of [`CHANGELOG.md`](CHANGELOG.md). If a new version starts sending data that this policy does not describe, the policy is changed in the same release, before that version is published. The license is in [`LICENSE`](LICENSE); components under their own licenses are in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

## 6. Your choices and rights

The author receives no personal data through the software, so the author holds nothing about you to show, correct, export or delete. You control the data on your computer yourself (section 7). The software sends data only to services you configure (section 2); you stop that by removing the service from the configuration. To exercise rights over data a service received (access, deletion, objection and others under the GDPR, the CCPA or other law), contact that service.

If you write to the author at the contact in section 5, the author uses your message and address only to answer you and keeps them no longer than needed for that.

## 7. Retention and deletion

Data on your computer stays until you delete it. To delete it:

- remove the configuration folder (`$CODELAB_HOME`, by default `~/.codelab`) with the configuration, session logs, agent logs and the secrets file;
- remove the app's `logs` folder in the application support folder of the operating system;
- uninstall the app; on most systems this also removes its per-user preferences, on others you remove them yourself;
- revoke API keys and tokens at the services that issued them, and delete conversations stored there under their own policies.

There is no account, so there is nothing to delete on the author's side.

## 8. Security

API keys are read from environment variables or kept in a file in the configuration folder that only your user can read (permissions `0600`); the software does not write key values to its logs. Connections to `https` and `wss` addresses are encrypted; a `ws://` or `http://` address that you configure yourself is not. No method of storage or transfer is fully secure, and the security of your computer and of the services you connect is outside the author's control (see [`TERMS.md`](TERMS.md), section 2).

## 9. Children

The software is a developer tool and is not directed at children under 13, or under the age of digital consent where you live. The author does not knowingly collect data from anyone, including children.

## 10. App stores and the operating system

App stores (the App Store, the Mac App Store, Google Play and others) and the operating system may collect data about downloads, purchases, crashes and device use under their own policies; that data goes to them. If you allow your system or store to share crash reports or diagnostics with app developers, the store may show the author aggregated or de-identified reports, and the author uses them only to find and fix defects.
