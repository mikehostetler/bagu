defmodule Moto.DynamicAgent.Spec do
  @moduledoc false

  alias Moto.ImportedAgent.Spec, as: ImportedSpec

  @enforce_keys [:name, :system_prompt, :model]
  defstruct [
    :name,
    :system_prompt,
    :model,
    context: %{},
    memory: nil,
    tools: [],
    subagents: [],
    plugins: [],
    hooks: %{before_turn: [], after_turn: [], on_interrupt: []},
    guardrails: %{input: [], output: [], tool: []}
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          system_prompt: String.t(),
          model: ImportedSpec.model_input(),
          context: map(),
          memory: Moto.Memory.config() | nil,
          tools: [String.t()],
          subagents: [map()],
          plugins: [String.t()],
          hooks: %{
            before_turn: [String.t()],
            after_turn: [String.t()],
            on_interrupt: [String.t()]
          },
          guardrails: %{
            input: [String.t()],
            output: [String.t()],
            tool: [String.t()]
          }
        }

  @spec schema() :: Zoi.schema()
  defdelegate schema(), to: ImportedSpec

  @spec new(map() | t(), keyword()) :: {:ok, t()} | {:error, term()}
  def new(%__MODULE__{} = spec, opts) do
    with {:ok, normalized_opts} <- normalize_registry_opts(opts) do
      spec
      |> unwrap()
      |> ImportedSpec.new(normalized_opts)
      |> wrap_result()
    end
  end

  def new(attrs, opts) when is_map(attrs) do
    with {:ok, normalized_opts} <- normalize_registry_opts(opts) do
      attrs
      |> ImportedSpec.new(normalized_opts)
      |> wrap_result()
    end
  end

  def new(other, opts), do: ImportedSpec.new(other, opts)

  @spec to_external_map(t()) :: map()
  def to_external_map(%__MODULE__{} = spec) do
    spec
    |> unwrap()
    |> ImportedSpec.to_external_map()
  end

  @spec fingerprint(t()) :: String.t()
  def fingerprint(%__MODULE__{} = spec) do
    spec
    |> unwrap()
    |> ImportedSpec.fingerprint()
  end

  @spec wrap(ImportedSpec.t()) :: t()
  def wrap(%ImportedSpec{} = spec), do: struct(__MODULE__, Map.from_struct(spec))

  @spec unwrap(t()) :: ImportedSpec.t()
  def unwrap(%__MODULE__{} = spec), do: struct(ImportedSpec, Map.from_struct(spec))

  defp wrap_result({:ok, %ImportedSpec{} = spec}), do: {:ok, wrap(spec)}
  defp wrap_result(other), do: other

  defp normalize_registry_opts(opts) when is_list(opts) do
    with {:ok, tools} <-
           normalize_opt(opts, :available_tools, &Moto.Tool.normalize_available_tools/1),
         {:ok, subagents} <-
           normalize_opt(
             opts,
             :available_subagents,
             &Moto.Subagent.normalize_available_subagents/1
           ),
         {:ok, plugins} <-
           normalize_opt(opts, :available_plugins, &Moto.Plugin.normalize_available_plugins/1),
         {:ok, hooks} <-
           normalize_opt(opts, :available_hooks, &Moto.Hook.normalize_available_hooks/1),
         {:ok, guardrails} <-
           normalize_opt(
             opts,
             :available_guardrails,
             &Moto.Guardrail.normalize_available_guardrails/1
           ) do
      {:ok,
       opts
       |> Keyword.put(:available_tools, tools)
       |> Keyword.put(:available_subagents, subagents)
       |> Keyword.put(:available_plugins, plugins)
       |> Keyword.put(:available_hooks, hooks)
       |> Keyword.put(:available_guardrails, guardrails)}
    end
  end

  defp normalize_opt(opts, key, normalizer) do
    opts
    |> Keyword.get(key, [])
    |> normalizer.()
  end
end
