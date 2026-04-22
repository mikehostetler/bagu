import Config

# Hooks are installed explicitly with `mix install_hooks` so secondary worktrees,
# detached PR checkouts, and automation environments stay safe.
config :git_hooks, auto_install: false
