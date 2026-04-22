defmodule Moto.Agent.SystemPrompt do
  @moduledoc false

  alias Jido.AI.Reasoning.ReAct.{Config, State}

  @callback resolve_system_prompt(input()) :: String.t() | {:ok, String.t()} | {:error, term()}

  @typedoc false
  @type input :: %{
          required(:request) => map(),
          required(:state) => State.t(),
          required(:config) => Config.t(),
          required(:context) => map()
        }

  @typedoc false
  @type spec :: String.t() | module() | {module(), atom(), [term()]}

  @spec normalize(module(), term()) ::
          {:ok, {:static, String.t()} | {:dynamic, spec()}} | {:error, String.t()}
  def normalize(_owner_module, system_prompt) when is_binary(system_prompt) do
    if String.trim(system_prompt) == "" do
      {:error, "system_prompt must not be empty"}
    else
      {:ok, {:static, system_prompt}}
    end
  end

  def normalize(_owner_module, {module, function, args} = spec)
      when is_atom(module) and is_atom(function) and is_list(args) do
    case Code.ensure_compiled(module) do
      {:module, ^module} ->
        arity = length(args) + 1

        if function_exported?(module, function, arity) do
          {:ok, {:dynamic, spec}}
        else
          {:error, "system_prompt MFA #{inspect(spec)} must export #{function}/#{arity} on #{inspect(module)}"}
        end

      {:error, reason} ->
        {:error, "system_prompt module #{inspect(module)} could not be loaded: #{inspect(reason)}"}
    end
  end

  def normalize(_owner_module, module) when is_atom(module) do
    case Code.ensure_compiled(module) do
      {:module, ^module} ->
        if function_exported?(module, :resolve_system_prompt, 1) do
          {:ok, {:dynamic, module}}
        else
          {:error, "system_prompt module #{inspect(module)} must implement resolve_system_prompt/1"}
        end

      {:error, reason} ->
        {:error, "system_prompt module #{inspect(module)} could not be loaded: #{inspect(reason)}"}
    end
  end

  def normalize(_owner_module, system_prompt) when is_function(system_prompt) do
    {:error, "system_prompt does not support anonymous functions; use a module callback or MFA instead"}
  end

  def normalize(_owner_module, other) do
    {:error,
     "system_prompt must be a string, a module implementing resolve_system_prompt/1, or an MFA tuple, got: #{inspect(other)}"}
  end

  @spec transform_request(spec(), map(), State.t(), Config.t(), map()) ::
          {:ok, %{messages: [map()]}} | {:error, term()}
  def transform_request(spec, request, %State{} = state, %Config{} = config, runtime_context)
      when is_map(request) and is_map(runtime_context) do
    input = %{
      request: request,
      state: state,
      config: config,
      context: runtime_context
    }

    with {:ok, prompt} <- resolve(spec, input) do
      {:ok, %{messages: put_system_prompt(Map.get(request, :messages, []), prompt)}}
    end
  end

  @spec resolve(spec(), input()) :: {:ok, String.t()} | {:error, term()}
  def resolve(spec, input)

  def resolve(prompt, _input) when is_binary(prompt), do: {:ok, prompt}

  def resolve(module, input) when is_atom(module) do
    module
    |> apply(:resolve_system_prompt, [input])
    |> normalize_result(module)
  rescue
    error ->
      {:error, "system_prompt module #{inspect(module)} failed: #{Exception.message(error)}"}
  end

  def resolve({module, function, args}, input) do
    module
    |> apply(function, [input | args])
    |> normalize_result({module, function, length(args) + 1})
  rescue
    error ->
      {:error,
       "system_prompt MFA #{inspect(module)}.#{function}/#{length(args) + 1} failed: #{Exception.message(error)}"}
  end

  defp normalize_result(prompt, _resolver) when is_binary(prompt) do
    if String.trim(prompt) == "" do
      {:error, "dynamic system_prompt must not resolve to an empty string"}
    else
      {:ok, prompt}
    end
  end

  defp normalize_result({:ok, prompt}, resolver) do
    normalize_result(prompt, resolver)
  end

  defp normalize_result({:error, reason}, _resolver), do: {:error, reason}

  defp normalize_result(other, resolver) do
    {:error,
     "dynamic system_prompt resolver #{inspect(resolver)} must return a string, {:ok, string}, or {:error, reason}; got: #{inspect(other)}"}
  end

  @spec put_system_prompt([map()], String.t()) :: [map()]
  def put_system_prompt(messages, prompt) when is_list(messages) and is_binary(prompt) do
    system_message = %{role: :system, content: prompt}

    case messages do
      [%{role: role} = _existing | rest] when role in [:system, "system"] ->
        [system_message | rest]

      _ ->
        [system_message | messages]
    end
  end

  @spec extract_system_prompt([map()]) :: String.t() | nil
  def extract_system_prompt([%{role: role, content: content} | _rest])
      when role in [:system, "system"] and is_binary(content) do
    content
  end

  def extract_system_prompt([_ | rest]), do: extract_system_prompt(rest)
  def extract_system_prompt([]), do: nil
end
