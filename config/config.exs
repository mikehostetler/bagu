import Config

config :moto,
  model_aliases: %{
    fast: "anthropic:claude-haiku-4-5"
  }

env_config = Path.expand("#{config_env()}.exs", __DIR__)

if File.exists?(env_config) do
  import_config "#{config_env()}.exs"
end
