defmodule Moto.DynamicAgent do
  @moduledoc false

  alias Moto.ImportedAgent

  @enforce_keys [
    :spec,
    :runtime_module,
    :tool_modules,
    :subagents,
    :plugin_modules,
    :hook_modules,
    :guardrail_modules
  ]
  defstruct [
    :spec,
    :runtime_module,
    :tool_modules,
    :subagents,
    :plugin_modules,
    :hook_modules,
    :guardrail_modules
  ]

  @type t :: %__MODULE__{
          spec: Moto.ImportedAgent.Spec.t() | Moto.DynamicAgent.Spec.t(),
          runtime_module: module(),
          tool_modules: [module()],
          subagents: [Moto.Subagent.t()],
          plugin_modules: [module()],
          hook_modules: Moto.Hooks.stage_map(),
          guardrail_modules: Moto.Guardrails.stage_map()
        }

  @spec import(
          map() | binary() | Moto.ImportedAgent.Spec.t() | Moto.DynamicAgent.Spec.t(),
          keyword()
        ) ::
          {:ok, t()} | {:error, term()}
  def import(source, opts \\ []) do
    source
    |> unwrap_spec()
    |> ImportedAgent.import(opts)
    |> case do
      {:ok, %ImportedAgent{} = agent} -> {:ok, wrap(agent)}
      other -> other
    end
  end

  @spec import_file(Path.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def import_file(path, opts \\ []) do
    case ImportedAgent.import_file(path, opts) do
      {:ok, %ImportedAgent{} = agent} -> {:ok, wrap(agent)}
      other -> other
    end
  end

  @spec start_link(t(), keyword()) :: DynamicSupervisor.on_start_child()
  def start_link(%__MODULE__{} = agent, opts \\ []) do
    agent
    |> unwrap()
    |> ImportedAgent.start_link(opts)
  end

  @spec encode(t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def encode(%__MODULE__{} = agent, opts \\ []) do
    agent
    |> unwrap()
    |> ImportedAgent.encode(opts)
  end

  @spec definition(t()) :: map()
  def definition(%__MODULE__{} = agent) do
    agent
    |> unwrap()
    |> ImportedAgent.definition()
  end

  @spec format_error(term()) :: String.t()
  defdelegate format_error(reason), to: ImportedAgent

  defp wrap(%ImportedAgent{} = agent), do: struct(__MODULE__, Map.from_struct(agent))
  defp unwrap(%__MODULE__{} = agent), do: struct(ImportedAgent, Map.from_struct(agent))
  defp unwrap_spec(%Moto.DynamicAgent.Spec{} = spec), do: Moto.DynamicAgent.Spec.unwrap(spec)
  defp unwrap_spec(source), do: source
end
