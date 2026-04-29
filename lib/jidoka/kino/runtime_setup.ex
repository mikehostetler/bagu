defmodule Jidoka.Kino.RuntimeSetup do
  @moduledoc false

  require Logger

  @provider_env_names ["ANTHROPIC_API_KEY", "LB_ANTHROPIC_API_KEY"]

  @spec provider_env_names() :: [String.t()]
  def provider_env_names, do: @provider_env_names

  @spec setup(keyword()) :: :ok
  def setup(opts \\ []) do
    show_raw_logs? = Keyword.get(opts, :show_raw_logs, false)
    log_level = if(show_raw_logs?, do: :notice, else: :warning)

    Logger.configure(level: log_level)
    Jidoka.Runtime.debug(if(show_raw_logs?, do: :on, else: :off))
    _ = load_provider_env(Keyword.get(opts, :provider_env, @provider_env_names))

    :ok
  end

  @spec start_or_reuse(String.t(), (-> {:ok, pid()} | {:error, term()})) ::
          {:ok, pid()} | {:error, term()}
  def start_or_reuse(id, start_fun) when is_binary(id) and is_function(start_fun, 0) do
    case Jidoka.Runtime.whereis(id) do
      nil -> start_fun.()
      pid -> {:ok, pid}
    end
  end

  @spec load_provider_env([String.t()]) :: {:ok, String.t()} | {:error, String.t()}
  def load_provider_env(names \\ @provider_env_names) when is_list(names) do
    case find_env(names) do
      nil ->
        clear_empty_env("ANTHROPIC_API_KEY")
        {:error, "Set ANTHROPIC_API_KEY, or a Livebook secret named ANTHROPIC_API_KEY"}

      {"ANTHROPIC_API_KEY", _key} ->
        {:ok, "ANTHROPIC_API_KEY"}

      {name, key} ->
        System.put_env("ANTHROPIC_API_KEY", key)
        {:ok, name}
    end
  end

  defp find_env(names) do
    Enum.find_value(names, fn name ->
      case System.get_env(name) do
        nil -> nil
        "" -> nil
        key -> {name, key}
      end
    end)
  end

  defp clear_empty_env(name) do
    if System.get_env(name) == "" do
      System.delete_env(name)
    end
  end
end
