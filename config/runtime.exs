import Config
import Dotenvy

app_root = System.get_env("RELEASE_ROOT") || Path.expand("..", __DIR__)

default_react_token_secret =
  :crypto.hash(:sha256, "moto:react_token_secret:#{Path.expand(app_root)}")
  |> Base.url_encode64(padding: false)

source!([
  System.get_env(),
  Path.join(app_root, ".env"),
  System.get_env()
])

config :req_llm,
  anthropic_api_key: env!("ANTHROPIC_API_KEY", :string, nil)

# Keep local demos and tests quiet with a stable per-workspace default while
# still allowing a real deployment secret to override it.
config :jido_ai,
  react_token_secret:
    env!("REACT_TOKEN_SECRET", :string, System.get_env("REACT_TOKEN_SECRET")) ||
      default_react_token_secret
