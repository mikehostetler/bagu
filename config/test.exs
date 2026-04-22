import Config

config :git_hooks, auto_install: false

mcp_sandbox = Path.expand("../tmp/mcp-sandbox", __DIR__)

# Live MCP integration tests use a real filesystem server pointed at this sandbox.
# The shell wrapper keeps server stderr out of normal ExUnit output.
config :jido_mcp, :endpoints,
  local_fs: %{
    transport:
      {:stdio,
       [
         command: "sh",
         args: [
           "-c",
           "exec npx -y @modelcontextprotocol/server-filesystem \"$1\" 2>/dev/null",
           "moto-fs-mcp",
           mcp_sandbox
         ]
       ]},
    client_info: %{name: "moto-test", version: "0.1.0"},
    timeouts: %{request_ms: 60_000}
  }
