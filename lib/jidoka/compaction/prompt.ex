defmodule Jidoka.Compaction.Prompt do
  @moduledoc """
  Behaviour for dynamic Jidoka compaction prompts.

  Use this when a static `prompt "..."` string is not enough. Jidoka calls
  `build_compaction_prompt/1` with sanitized compaction input and appends the
  transcript payload separately before asking the summarizer to compress older
  messages.
  """

  @type input :: %{
          optional(:agent) => Jido.Agent.t(),
          optional(:config) => map(),
          optional(:context) => map(),
          optional(:previous_summary) => String.t() | nil,
          optional(:request_id) => String.t() | nil,
          optional(:source_message_count) => non_neg_integer(),
          optional(:retained_message_count) => non_neg_integer(),
          optional(:transcript) => String.t()
        }

  @type spec :: String.t() | module() | {module(), atom(), [term()]}

  @doc """
  Builds a summarizer system prompt from sanitized compaction input.
  """
  @callback build_compaction_prompt(input()) :: String.t() | {:ok, String.t()} | {:error, term()}

  @default_prompt """
  Compress the conversation for the next agent turn.

  Preserve only durable context:
  - active user goal, constraints, preferences, and success criteria
  - decisions made, facts learned, IDs, files, entities, and runtime context
  - tool, workflow, subagent, handoff, memory, and guardrail outcomes
  - unresolved tasks, errors, warnings, open questions, and next steps

  Be concise and faithful. Do not invent facts; mark uncertainty clearly.
  Exclude secrets, credentials, irrelevant logs, and conversational filler.
  Return only the summary text.
  """

  @doc """
  Returns Jidoka's built-in summary compaction prompt.
  """
  @spec default_prompt() :: String.t()
  def default_prompt, do: @default_prompt

  @doc false
  @spec normalize(module() | nil, term(), keyword()) :: {:ok, spec() | nil} | {:error, String.t()}
  def normalize(owner_module, prompt, opts \\ [])
  def normalize(_owner_module, nil, _opts), do: {:ok, nil}

  def normalize(_owner_module, prompt, opts) when is_binary(prompt) do
    if String.trim(prompt) == "" do
      {:error, "#{label(opts)} must not be empty"}
    else
      {:ok, prompt}
    end
  end

  def normalize(_owner_module, {module, function, args} = spec, opts)
      when is_atom(module) and is_atom(function) and is_list(args) do
    case Code.ensure_compiled(module) do
      {:module, ^module} ->
        arity = length(args) + 1

        if function_exported?(module, function, arity) do
          {:ok, spec}
        else
          {:error, "#{label(opts)} MFA #{inspect(spec)} must export #{function}/#{arity} on #{inspect(module)}"}
        end

      {:error, reason} ->
        {:error, "#{label(opts)} module #{inspect(module)} could not be loaded: #{inspect(reason)}"}
    end
  end

  def normalize(_owner_module, module, opts) when is_atom(module) do
    case Code.ensure_compiled(module) do
      {:module, ^module} ->
        if function_exported?(module, :build_compaction_prompt, 1) do
          {:ok, module}
        else
          {:error, "#{label(opts)} module #{inspect(module)} must implement build_compaction_prompt/1"}
        end

      {:error, reason} ->
        {:error, "#{label(opts)} module #{inspect(module)} could not be loaded: #{inspect(reason)}"}
    end
  end

  def normalize(_owner_module, prompt, opts) when is_function(prompt) do
    {:error, "#{label(opts)} does not support anonymous functions; use a module callback or MFA instead"}
  end

  def normalize(_owner_module, other, opts) do
    {:error,
     "#{label(opts)} must be a string, a module implementing build_compaction_prompt/1, or an MFA tuple, got: #{inspect(other)}"}
  end

  @doc false
  @spec resolve(spec() | nil, input()) :: {:ok, String.t()} | {:error, term()}
  def resolve(nil, _input), do: {:ok, @default_prompt}
  def resolve(prompt, _input) when is_binary(prompt), do: {:ok, prompt}

  def resolve(module, input) when is_atom(module) do
    module
    |> apply(:build_compaction_prompt, [input])
    |> normalize_result(module)
  rescue
    error ->
      {:error, "compaction prompt module #{inspect(module)} failed: #{Exception.message(error)}"}
  end

  def resolve({module, function, args}, input) do
    module
    |> apply(function, [input | args])
    |> normalize_result({module, function, length(args) + 1})
  rescue
    error ->
      {:error,
       "compaction prompt MFA #{inspect(module)}.#{function}/#{length(args) + 1} failed: #{Exception.message(error)}"}
  end

  defp normalize_result(prompt, _resolver) when is_binary(prompt) do
    if String.trim(prompt) == "" do
      {:error, "dynamic compaction prompt must not resolve to an empty string"}
    else
      {:ok, prompt}
    end
  end

  defp normalize_result({:ok, prompt}, resolver), do: normalize_result(prompt, resolver)
  defp normalize_result({:error, reason}, _resolver), do: {:error, reason}

  defp normalize_result(other, resolver) do
    {:error,
     "dynamic compaction prompt resolver #{inspect(resolver)} must return a string, {:ok, string}, or {:error, reason}; got: #{inspect(other)}"}
  end

  defp label(opts), do: Keyword.get(opts, :label, "compaction prompt")
end
