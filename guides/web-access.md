# Web Access

The `web` capability gives an agent a small, opinionated set of read-only
web tools backed by `jido_browser`. Use it when the agent needs to search
the public web or read a known URL. The capability is intentionally narrow
so the model cannot navigate, click, type, run JavaScript, submit forms,
manage tabs, or persist browser state.

## Minimal Example

```elixir
capabilities do
  web :read_only
end
```

Or, search-only:

```elixir
capabilities do
  web :search
end
```

Declare at most one `web` entry per agent.

## Modes And Tools

`web :search` exposes:

- `search_web`: Brave Search through `jido_browser`.

`web :read_only` exposes:

- `search_web`
- `read_page`: fetches a public page and returns extracted text content.
- `snapshot_url`: captures a structured snapshot of a public page.

Default response limits are bounded (search results capped, extracted
content truncated to a fixed character budget). The truncation is part of
the contract, not a soft suggestion.

## Setup

Search requires a Brave API key:

```bash
export BRAVE_SEARCH_API_KEY=...
```

or, in app config:

```elixir
config :jido_browser, :brave_api_key, "..."
```

Page reading requires the `jido_browser` runtime backend:

```bash
mix jido_browser.install --if-missing
```

## SSRF Posture

`read_page` and `snapshot_url` validate URLs before launching the
browser:

- Only `http` and `https` schemes are accepted.
- Localhost and loopback addresses are rejected.
- Private network addresses (RFC 1918 and link-local ranges) are
  rejected.

This happens before any network I/O so a misuse cannot reach internal
services. The Jidoka public DSL never exposes raw browser automation.

## See Also

- [tools.md](./tools.md)
- [plugins.md](./plugins.md)
- [mcp-tools.md](./mcp-tools.md)
- [agents.md](./agents.md)
- [errors.md](./errors.md)

## Imported Agents

Imported specs opt into web access using mode strings only:

```json
{
  "capabilities": {
    "web": [{"mode": "read_only"}]
  }
}
```

Both `"search"` and `"read_only"` are accepted. Imported web capabilities
do not accept module strings or arbitrary browser configuration; the API
key and `jido_browser` install steps are still done in application code.
See [imported-agents.md](./imported-agents.md).
