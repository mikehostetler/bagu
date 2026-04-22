defmodule Moto.Subagent.Definition do
  @moduledoc false

  @required_functions [
    {:name, 0},
    {:chat, 3},
    {:start_link, 1},
    {:runtime_module, 0}
  ]

  @default_timeout 30_000
  @default_forward_context :public
  @default_result :text

  @spec validate_agent_module(module()) :: :ok | {:error, String.t()}
  def validate_agent_module(module) when is_atom(module) do
    cond do
      match?({:error, _}, Code.ensure_compiled(module)) ->
        {:error, "subagent #{inspect(module)} could not be loaded"}

      missing = missing_functions(module) ->
        {:error,
         "subagent #{inspect(module)} is not a valid Moto subagent; missing #{Enum.join(missing, ", ")}"}

      true ->
        agent_name(module)
        |> case do
          {:ok, _name} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  def validate_agent_module(other),
    do: {:error, "subagent entries must be modules, got: #{inspect(other)}"}

  @spec agent_name(module()) :: {:ok, Moto.Subagent.name()} | {:error, String.t()}
  def agent_name(module) when is_atom(module) do
    with :ok <- ensure_compiled_agent(module),
         published_name when is_binary(published_name) <- module.name(),
         trimmed <- String.trim(published_name),
         :ok <- validate_published_name(trimmed, :agent) do
      {:ok, trimmed}
    else
      {:error, reason} ->
        {:error, reason}

      _ ->
        {:error, "subagent #{inspect(module)} must publish a non-empty string name"}
    end
  end

  def agent_name(other),
    do: {:error, "subagent entries must be modules, got: #{inspect(other)}"}

  @spec subagent_names([Moto.Subagent.t()]) ::
          {:ok, [Moto.Subagent.name()]} | {:error, String.t()}
  def subagent_names(subagents) when is_list(subagents) do
    names = Enum.map(subagents, & &1.name)

    if Enum.uniq(names) == names do
      {:ok, names}
    else
      {:error, "subagent names must be unique within a Moto agent"}
    end
  end

  @spec new(module(), keyword()) :: {:ok, Moto.Subagent.t()} | {:error, String.t()}
  def new(agent_module, opts \\ []) when is_atom(agent_module) and is_list(opts) do
    with :ok <- validate_agent_module(agent_module),
         {:ok, default_name} <- agent_name(agent_module),
         published_name <- Keyword.get(opts, :as) || default_name,
         {:ok, normalized_name} <- normalize_subagent_name(published_name),
         {:ok, description} <-
           normalize_description(
             Keyword.get(opts, :description) ||
               "Ask #{normalized_name} to handle a specialist task."
           ),
         {:ok, target} <- normalize_target(Keyword.get(opts, :target) || :ephemeral),
         {:ok, timeout} <- normalize_timeout(Keyword.get(opts, :timeout, @default_timeout)),
         {:ok, forward_context} <-
           normalize_forward_context(
             Keyword.get(opts, :forward_context, @default_forward_context)
           ),
         {:ok, result} <- normalize_result(Keyword.get(opts, :result, @default_result)) do
      {:ok,
       %Moto.Subagent{
         agent: agent_module,
         name: normalized_name,
         description: description,
         target: target,
         timeout: timeout,
         forward_context: forward_context,
         result: result
       }}
    end
  end

  @spec normalize_available_subagents([module()] | %{required(Moto.Subagent.name()) => module()}) ::
          {:ok, Moto.Subagent.registry()} | {:error, String.t()}
  def normalize_available_subagents(modules) when is_list(modules) do
    modules
    |> Enum.reduce_while({:ok, %{}}, fn module, {:ok, acc} ->
      with {:ok, name} <- agent_name(module),
           :ok <- ensure_unique_registry_name(name, acc) do
        {:cont, {:ok, Map.put(acc, name, module)}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  def normalize_available_subagents(registry) when is_map(registry) do
    registry
    |> Enum.reduce_while({:ok, %{}}, fn {name, module}, {:ok, acc} ->
      with true <- is_binary(name) or {:error, "subagent registry keys must be strings"},
           trimmed <- String.trim(name),
           :ok <- validate_published_name(trimmed, :agent),
           {:ok, published_name} <- agent_name(module),
           true <-
             trimmed == published_name or
               {:error,
                "subagent registry key #{inspect(trimmed)} must match published agent name #{inspect(published_name)}"},
           :ok <- ensure_unique_registry_name(trimmed, acc) do
        {:cont, {:ok, Map.put(acc, trimmed, module)}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
        false -> {:halt, {:error, "subagent registry keys must be non-empty strings"}}
      end
    end)
  end

  def normalize_available_subagents(other),
    do:
      {:error,
       "available_subagents must be a list of Moto agent modules or a map of name => module, got: #{inspect(other)}"}

  @spec resolve_subagent_name(Moto.Subagent.name(), Moto.Subagent.registry()) ::
          {:ok, module()} | {:error, String.t()}
  def resolve_subagent_name(name, registry) when is_binary(name) and is_map(registry) do
    case Map.fetch(registry, name) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, "unknown subagent #{inspect(name)}"}
    end
  end

  def resolve_subagent_name(_name, _registry),
    do: {:error, "subagent name must be a string and registry must be a map"}

  @spec normalize_target(term()) :: {:ok, Moto.Subagent.target()} | {:error, String.t()}
  def normalize_target(:ephemeral), do: {:ok, :ephemeral}
  def normalize_target("ephemeral"), do: {:ok, :ephemeral}

  def normalize_target({:peer, peer_id}) when is_binary(peer_id) do
    trimmed = String.trim(peer_id)

    if trimmed == "" do
      {:error, "subagent peer ids must not be empty"}
    else
      {:ok, {:peer, trimmed}}
    end
  end

  def normalize_target({:peer, {:context, key}}) when is_atom(key) or is_binary(key) do
    {:ok, {:peer, {:context, key}}}
  end

  def normalize_target(other) do
    {:error,
     "subagent target must be :ephemeral, {:peer, \"id\"}, or {:peer, {:context, key}}, got: #{inspect(other)}"}
  end

  @spec normalize_timeout(term()) :: {:ok, pos_integer()} | {:error, String.t()}
  def normalize_timeout(timeout) when is_integer(timeout) and timeout > 0, do: {:ok, timeout}

  def normalize_timeout(other),
    do:
      {:error,
       "subagent timeout must be a positive integer in milliseconds, got: #{inspect(other)}"}

  @spec normalize_forward_context(term()) ::
          {:ok, Moto.Subagent.forward_context()} | {:error, String.t()}
  def normalize_forward_context(:public), do: {:ok, :public}
  def normalize_forward_context("public"), do: {:ok, :public}
  def normalize_forward_context(:none), do: {:ok, :none}
  def normalize_forward_context("none"), do: {:ok, :none}

  def normalize_forward_context({mode, keys}) when mode in [:only, :except] do
    normalize_forward_context_keys(mode, keys)
  end

  def normalize_forward_context(%{mode: mode, keys: keys}) do
    mode
    |> normalize_forward_context_mode()
    |> case do
      {:ok, :only} -> normalize_forward_context_keys(:only, keys)
      {:ok, :except} -> normalize_forward_context_keys(:except, keys)
      {:ok, mode} -> {:ok, mode}
      {:error, reason} -> {:error, reason}
    end
  end

  def normalize_forward_context(%{"mode" => mode, "keys" => keys}) do
    normalize_forward_context(%{mode: mode, keys: keys})
  end

  def normalize_forward_context(%{mode: mode}) do
    case normalize_forward_context_mode(mode) do
      {:ok, mode} when mode in [:public, :none] -> {:ok, mode}
      {:ok, mode} -> normalize_forward_context_keys(mode, nil)
      {:error, reason} -> {:error, reason}
    end
  end

  def normalize_forward_context(%{"mode" => mode}) do
    normalize_forward_context(%{mode: mode})
  end

  def normalize_forward_context(other),
    do:
      {:error,
       "subagent forward_context must be :public, :none, {:only, keys}, or {:except, keys}, got: #{inspect(other)}"}

  @spec normalize_result(term()) :: {:ok, Moto.Subagent.result_mode()} | {:error, String.t()}
  def normalize_result(:text), do: {:ok, :text}
  def normalize_result("text"), do: {:ok, :text}
  def normalize_result(:structured), do: {:ok, :structured}
  def normalize_result("structured"), do: {:ok, :structured}

  def normalize_result(other),
    do: {:error, "subagent result must be :text or :structured, got: #{inspect(other)}"}

  defp normalize_subagent_name(name) when is_binary(name) do
    trimmed = String.trim(name)

    case validate_published_name(trimmed, :tool) do
      :ok -> {:ok, trimmed}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_subagent_name(other),
    do: {:error, "subagent names must be non-empty strings, got: #{inspect(other)}"}

  defp normalize_description(description) when is_binary(description) do
    trimmed = String.trim(description)

    if trimmed == "" do
      {:error, "subagent descriptions must not be empty"}
    else
      {:ok, trimmed}
    end
  end

  defp normalize_description(other),
    do: {:error, "subagent descriptions must be strings, got: #{inspect(other)}"}

  defp normalize_forward_context_mode(:public), do: {:ok, :public}
  defp normalize_forward_context_mode("public"), do: {:ok, :public}
  defp normalize_forward_context_mode(:none), do: {:ok, :none}
  defp normalize_forward_context_mode("none"), do: {:ok, :none}
  defp normalize_forward_context_mode(:only), do: {:ok, :only}
  defp normalize_forward_context_mode("only"), do: {:ok, :only}
  defp normalize_forward_context_mode(:except), do: {:ok, :except}
  defp normalize_forward_context_mode("except"), do: {:ok, :except}

  defp normalize_forward_context_mode(other),
    do:
      {:error,
       "subagent forward_context mode must be public, none, only, or except, got: #{inspect(other)}"}

  defp normalize_forward_context_keys(mode, keys) when is_list(keys) do
    keys
    |> Enum.reduce_while({:ok, []}, fn key, {:ok, acc} ->
      case normalize_forward_context_key(key) do
        {:ok, normalized_key} -> {:cont, {:ok, acc ++ [normalized_key]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, normalized_keys} -> {:ok, {mode, normalized_keys}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_forward_context_keys(_mode, other),
    do: {:error, "subagent forward_context keys must be a list, got: #{inspect(other)}"}

  defp normalize_forward_context_key(key) when is_atom(key), do: {:ok, key}

  defp normalize_forward_context_key(key) when is_binary(key) do
    case String.trim(key) do
      "" -> {:error, "subagent forward_context keys must not be empty"}
      trimmed -> {:ok, trimmed}
    end
  end

  defp normalize_forward_context_key(other),
    do: {:error, "subagent forward_context keys must be atoms or strings, got: #{inspect(other)}"}

  defp validate_published_name("", _kind),
    do: {:error, "subagent names must not be empty"}

  defp validate_published_name(name, :tool) do
    if String.match?(name, ~r/^[a-z][a-z0-9_]*$/) do
      :ok
    else
      {:error,
       "subagent tool names must start with a lowercase letter and contain only lowercase letters, numbers, and underscores"}
    end
  end

  defp validate_published_name(name, :agent) do
    if String.match?(name, ~r/^[A-Za-z0-9][A-Za-z0-9_-]*$/) do
      :ok
    else
      {:error,
       "subagent agent names must start with a letter or number and contain only letters, numbers, underscores, and hyphens"}
    end
  end

  defp ensure_compiled_agent(module) do
    cond do
      match?({:error, _}, Code.ensure_compiled(module)) ->
        {:error, "subagent #{inspect(module)} could not be loaded"}

      missing = missing_functions(module) ->
        {:error,
         "subagent #{inspect(module)} is not a valid Moto subagent; missing #{Enum.join(missing, ", ")}"}

      true ->
        :ok
    end
  end

  defp missing_functions(module) do
    @required_functions
    |> Enum.reject(fn {name, arity} -> function_exported?(module, name, arity) end)
    |> Enum.map(fn {name, arity} -> "#{name}/#{arity}" end)
    |> case do
      [] -> nil
      missing -> missing
    end
  end

  defp ensure_unique_registry_name(name, acc) do
    if Map.has_key?(acc, name) do
      {:error, "subagent names must be unique within a Moto subagent registry"}
    else
      :ok
    end
  end
end
