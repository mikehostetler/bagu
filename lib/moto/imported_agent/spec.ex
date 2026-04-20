defmodule Moto.ImportedAgent.Spec do
  @moduledoc false

  @name_schema [
    Zoi.string()
    |> Zoi.trim()
    |> Zoi.min(1)
    |> Zoi.max(64)
    |> Zoi.regex(~r/^[A-Za-z0-9][A-Za-z0-9_-]*$/)
  ]

  @prompt_schema [
    Zoi.string()
    |> Zoi.min(1)
    |> Zoi.max(50_000)
  ]

  @tool_name_schema Zoi.string()
                    |> Zoi.trim()
                    |> Zoi.min(1)
                    |> Zoi.max(128)
                    |> Zoi.regex(~r/^[a-z][a-z0-9_]*$/)

  @plugin_name_schema Zoi.string()
                      |> Zoi.trim()
                      |> Zoi.min(1)
                      |> Zoi.max(128)
                      |> Zoi.regex(~r/^[a-z][a-z0-9_]*$/)

  @subagent_agent_name_schema Zoi.string()
                              |> Zoi.trim()
                              |> Zoi.min(1)
                              |> Zoi.max(128)
                              |> Zoi.regex(~r/^[A-Za-z0-9][A-Za-z0-9_-]*$/)

  @subagent_tool_name_schema Zoi.string()
                             |> Zoi.trim()
                             |> Zoi.min(1)
                             |> Zoi.max(128)
                             |> Zoi.regex(~r/^[a-z][a-z0-9_]*$/)

  @hook_name_schema Zoi.string()
                    |> Zoi.trim()
                    |> Zoi.min(1)
                    |> Zoi.max(128)
                    |> Zoi.regex(~r/^[a-z][a-z0-9_]*$/)

  @guardrail_name_schema Zoi.string()
                         |> Zoi.trim()
                         |> Zoi.min(1)
                         |> Zoi.max(128)
                         |> Zoi.regex(~r/^[a-z][a-z0-9_]*$/)

  @default_hooks %{before_turn: [], after_turn: [], on_interrupt: []}
  @default_guardrails %{input: [], output: [], tool: []}
  @default_memory nil
  @default_subagents []

  @model_map_schema Zoi.object(
                      %{
                        provider:
                          Zoi.string()
                          |> Zoi.trim()
                          |> Zoi.min(1)
                          |> Zoi.max(64),
                        id:
                          Zoi.string()
                          |> Zoi.trim()
                          |> Zoi.min(1)
                          |> Zoi.max(256),
                        base_url:
                          Zoi.string()
                          |> Zoi.trim()
                          |> Zoi.min(1)
                          |> Zoi.max(2_048)
                          |> Zoi.optional()
                      },
                      coerce: true,
                      unrecognized_keys: :error
                    )

  @hooks_schema Zoi.object(
                  %{
                    before_turn: Zoi.list(@hook_name_schema) |> Zoi.default([]),
                    after_turn: Zoi.list(@hook_name_schema) |> Zoi.default([]),
                    on_interrupt: Zoi.list(@hook_name_schema) |> Zoi.default([])
                  },
                  coerce: true,
                  unrecognized_keys: :error
                )

  @subagent_schema Zoi.object(
                     %{
                       agent: @subagent_agent_name_schema,
                       as: @subagent_tool_name_schema |> Zoi.optional(),
                       description:
                         Zoi.string()
                         |> Zoi.trim()
                         |> Zoi.min(1)
                         |> Zoi.max(1_000)
                         |> Zoi.optional(),
                       target:
                         Zoi.string()
                         |> Zoi.trim()
                         |> Zoi.min(1)
                         |> Zoi.default("ephemeral"),
                       peer_id:
                         Zoi.string()
                         |> Zoi.trim()
                         |> Zoi.min(1)
                         |> Zoi.optional(),
                       peer_id_context_key:
                         Zoi.union([Zoi.string() |> Zoi.trim() |> Zoi.min(1), Zoi.atom()])
                         |> Zoi.optional()
                     },
                     coerce: true,
                     unrecognized_keys: :error
                   )

  @guardrails_schema Zoi.object(
                       %{
                         input: Zoi.list(@guardrail_name_schema) |> Zoi.default([]),
                         output: Zoi.list(@guardrail_name_schema) |> Zoi.default([]),
                         tool: Zoi.list(@guardrail_name_schema) |> Zoi.default([])
                       },
                       coerce: true,
                       unrecognized_keys: :error
                     )

  @memory_retrieve_schema Zoi.object(
                            %{
                              limit: Zoi.integer() |> Zoi.default(5)
                            },
                            coerce: true,
                            unrecognized_keys: :error
                          )

  @memory_schema Zoi.object(
                   %{
                     mode:
                       Zoi.string()
                       |> Zoi.trim()
                       |> Zoi.min(1)
                       |> Zoi.default("conversation"),
                     namespace:
                       Zoi.string()
                       |> Zoi.trim()
                       |> Zoi.min(1)
                       |> Zoi.default("per_agent"),
                     shared_namespace:
                       Zoi.string()
                       |> Zoi.trim()
                       |> Zoi.min(1)
                       |> Zoi.optional(),
                     context_namespace_key:
                       Zoi.union([Zoi.string() |> Zoi.trim() |> Zoi.min(1), Zoi.atom()])
                       |> Zoi.optional(),
                     capture:
                       Zoi.string()
                       |> Zoi.trim()
                       |> Zoi.min(1)
                       |> Zoi.default("conversation"),
                     retrieve: @memory_retrieve_schema |> Zoi.default(%{limit: 5}),
                     inject:
                       Zoi.string()
                       |> Zoi.trim()
                       |> Zoi.min(1)
                       |> Zoi.default("system_prompt")
                   },
                   coerce: true,
                   unrecognized_keys: :error
                 )

  @schema Zoi.struct(
            __MODULE__,
            %{
              name: hd(@name_schema),
              system_prompt: hd(@prompt_schema),
              model:
                Zoi.union([
                  Zoi.string() |> Zoi.trim() |> Zoi.min(1) |> Zoi.max(256),
                  @model_map_schema
                ]),
              context: Zoi.map() |> Zoi.default(%{}),
              memory: Zoi.union([@memory_schema, Zoi.literal(nil)]) |> Zoi.default(nil),
              tools: Zoi.list(@tool_name_schema) |> Zoi.default([]),
              subagents: Zoi.list(@subagent_schema) |> Zoi.default(@default_subagents),
              plugins: Zoi.list(@plugin_name_schema) |> Zoi.default([]),
              hooks: @hooks_schema |> Zoi.default(@default_hooks),
              guardrails: @guardrails_schema |> Zoi.default(@default_guardrails)
            },
            coerce: true,
            unrecognized_keys: :error
          )

  @type model_input ::
          atom()
          | String.t()
          | %{
              required(:provider) => String.t(),
              required(:id) => String.t(),
              optional(:base_url) => String.t()
            }
  @type t :: %__MODULE__{
          name: String.t(),
          system_prompt: String.t(),
          model: model_input(),
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

  @enforce_keys [:name, :system_prompt, :model]
  defstruct [
    :name,
    :system_prompt,
    :model,
    context: %{},
    memory: @default_memory,
    tools: [],
    subagents: @default_subagents,
    plugins: [],
    hooks: @default_hooks,
    guardrails: @default_guardrails
  ]

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec new(map() | t(), keyword()) :: {:ok, t()} | {:error, term()}
  def new(%__MODULE__{} = spec, opts) do
    with :ok <- validate_context(spec.context),
         {:ok, normalized_memory} <- Moto.Memory.normalize_imported(spec.memory),
         {:ok, spec} <- validate_tools(spec, Keyword.get(opts, :available_tools, %{})),
         {:ok, spec} <- validate_subagents(spec, Keyword.get(opts, :available_subagents, %{})),
         {:ok, spec} <- validate_plugins(spec, Keyword.get(opts, :available_plugins, %{})),
         {:ok, spec} <- validate_hooks(spec, Keyword.get(opts, :available_hooks, %{})) do
      validate_guardrails(
        %{spec | memory: normalized_memory},
        Keyword.get(opts, :available_guardrails, %{})
      )
    end
  end

  def new(attrs, opts) when is_map(attrs) do
    with {:ok, spec} <- Zoi.parse(@schema, attrs),
         {:ok, normalized_model} <- normalize_model(spec.model),
         :ok <- validate_model(normalized_model),
         :ok <- validate_context(spec.context),
         {:ok, normalized_memory} <- Moto.Memory.normalize_imported(spec.memory),
         {:ok, normalized_spec} <-
           validate_tools(
             %{spec | model: normalized_model, memory: normalized_memory},
             Keyword.get(opts, :available_tools, %{})
           ),
         {:ok, normalized_spec} <-
           validate_subagents(
             normalized_spec,
             Keyword.get(opts, :available_subagents, %{})
           ),
         {:ok, normalized_spec} <-
           validate_plugins(
             normalized_spec,
             Keyword.get(opts, :available_plugins, %{})
           ),
         {:ok, normalized_spec} <-
           validate_hooks(
             normalized_spec,
             Keyword.get(opts, :available_hooks, %{})
           ),
         {:ok, normalized_spec} <-
           validate_guardrails(
             normalized_spec,
             Keyword.get(opts, :available_guardrails, %{})
           ) do
      {:ok, normalized_spec}
    else
      {:error, [%Zoi.Error{} | _] = errors} ->
        {:error, format_zoi_errors(errors)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def new(other, _opts),
    do: {:error, "imported Moto agent specs must be maps, got: #{inspect(other)}"}

  @spec to_external_map(t()) :: map()
  def to_external_map(%__MODULE__{} = spec) do
    %{
      "name" => spec.name,
      "model" => externalize_model(spec.model),
      "system_prompt" => spec.system_prompt,
      "context" => spec.context,
      "memory" => externalize_memory(spec.memory),
      "tools" => spec.tools,
      "subagents" => spec.subagents,
      "plugins" => spec.plugins,
      "hooks" => spec.hooks,
      "guardrails" => spec.guardrails
    }
  end

  @spec fingerprint(t()) :: String.t()
  def fingerprint(%__MODULE__{} = spec) do
    spec
    |> to_external_map()
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp normalize_model(model) when is_binary(model) do
    trimmed = String.trim(model)

    cond do
      trimmed == "" ->
        {:error, "model must not be empty"}

      String.contains?(trimmed, ":") ->
        {:ok, trimmed}

      true ->
        case alias_atom(trimmed) do
          {:ok, alias_name} ->
            {:ok, alias_name}

          :error ->
            {:error,
             "model must be a known alias string like \"fast\" or a direct provider:model string"}
        end
    end
  end

  defp normalize_model(%{} = model) do
    normalized =
      model
      |> Map.take([:provider, :id, :base_url])
      |> Enum.reduce(%{}, fn
        {:base_url, nil}, acc -> acc
        {key, value}, acc when is_binary(value) -> Map.put(acc, key, String.trim(value))
        {key, value}, acc -> Map.put(acc, key, value)
      end)

    {:ok, normalized}
  end

  defp validate_model(model) do
    model
    |> Moto.model()
    |> ReqLLM.model()
    |> case do
      {:ok, _model} -> :ok
      {:error, reason} -> {:error, format_model_error(reason)}
    end
  end

  defp validate_context(context) do
    case Moto.Context.validate_default(context) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp alias_atom(name) do
    (Map.keys(Moto.model_aliases()) ++ Map.keys(Jido.AI.model_aliases()))
    |> Enum.uniq()
    |> Enum.find_value(:error, fn alias_name ->
      if Atom.to_string(alias_name) == name, do: {:ok, alias_name}, else: false
    end)
  end

  defp externalize_model(model) when is_atom(model), do: Atom.to_string(model)
  defp externalize_model(model), do: model

  defp externalize_memory(nil), do: nil

  defp externalize_memory(%{namespace: :per_agent} = memory) do
    %{
      "mode" => Atom.to_string(memory.mode),
      "namespace" => "per_agent",
      "capture" => Atom.to_string(memory.capture),
      "retrieve" => %{"limit" => memory.retrieve.limit},
      "inject" => Atom.to_string(memory.inject)
    }
  end

  defp externalize_memory(%{namespace: {:shared, shared_namespace}} = memory) do
    %{
      "mode" => Atom.to_string(memory.mode),
      "namespace" => "shared",
      "shared_namespace" => shared_namespace,
      "capture" => Atom.to_string(memory.capture),
      "retrieve" => %{"limit" => memory.retrieve.limit},
      "inject" => Atom.to_string(memory.inject)
    }
  end

  defp externalize_memory(%{namespace: {:context, key}} = memory) do
    %{
      "mode" => Atom.to_string(memory.mode),
      "namespace" => "context",
      "context_namespace_key" => key,
      "capture" => Atom.to_string(memory.capture),
      "retrieve" => %{"limit" => memory.retrieve.limit},
      "inject" => Atom.to_string(memory.inject)
    }
  end

  defp validate_tools(%__MODULE__{} = spec, available_tools) when is_map(available_tools) do
    cond do
      Enum.uniq(spec.tools) != spec.tools ->
        {:error, "tools must be unique"}

      spec.tools == [] ->
        {:ok, spec}

      map_size(available_tools) == 0 ->
        {:error, "tools require an available_tools registry when importing Moto agents"}

      true ->
        case Moto.Tool.resolve_tool_names(spec.tools, available_tools) do
          {:ok, _tool_modules} -> {:ok, spec}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp validate_plugins(%__MODULE__{} = spec, available_plugins) when is_map(available_plugins) do
    cond do
      Enum.uniq(spec.plugins) != spec.plugins ->
        {:error, "plugins must be unique"}

      spec.plugins == [] ->
        {:ok, spec}

      map_size(available_plugins) == 0 ->
        {:error, "plugins require an available_plugins registry when importing Moto agents"}

      true ->
        case Moto.Plugin.resolve_plugin_names(spec.plugins, available_plugins) do
          {:ok, _plugin_modules} -> {:ok, spec}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp validate_subagents(%__MODULE__{} = spec, available_subagents)
       when is_map(available_subagents) do
    cond do
      not subagents_unique?(spec.subagents) ->
        {:error, "subagent names must be unique"}

      spec.subagents == [] ->
        {:ok, spec}

      map_size(available_subagents) == 0 ->
        {:error, "subagents require an available_subagents registry when importing Moto agents"}

      true ->
        spec.subagents
        |> Enum.reduce_while({:ok, spec}, fn subagent, {:ok, spec_acc} ->
          with {:ok, agent_module} <-
                 Moto.Subagent.resolve_subagent_name(subagent.agent, available_subagents),
               {:ok, _normalized} <-
                 Moto.Subagent.new(
                   agent_module,
                   as: Map.get(subagent, :as),
                   description: Map.get(subagent, :description),
                   target: imported_subagent_target(subagent)
                 ) do
            {:cont, {:ok, spec_acc}}
          else
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
    end
  end

  defp validate_hooks(%__MODULE__{} = spec, available_hooks) when is_map(available_hooks) do
    cond do
      not hooks_unique?(spec.hooks) ->
        {:error, "hook names must be unique within each stage"}

      hooks_empty?(spec.hooks) ->
        {:ok, spec}

      map_size(available_hooks) == 0 ->
        {:error, "hooks require an available_hooks registry when importing Moto agents"}

      true ->
        spec.hooks
        |> Enum.reduce_while({:ok, spec}, fn {_stage, hook_names}, {:ok, spec_acc} ->
          case Moto.Hook.resolve_hook_names(hook_names, available_hooks) do
            {:ok, _hook_modules} -> {:cont, {:ok, spec_acc}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
    end
  end

  defp validate_guardrails(%__MODULE__{} = spec, available_guardrails)
       when is_map(available_guardrails) do
    cond do
      not guardrails_unique?(spec.guardrails) ->
        {:error, "guardrail names must be unique within each stage"}

      guardrails_empty?(spec.guardrails) ->
        {:ok, spec}

      map_size(available_guardrails) == 0 ->
        {:error, "guardrails require an available_guardrails registry when importing Moto agents"}

      true ->
        spec.guardrails
        |> Enum.reduce_while({:ok, spec}, fn {_stage, guardrail_names}, {:ok, spec_acc} ->
          case Moto.Guardrail.resolve_guardrail_names(guardrail_names, available_guardrails) do
            {:ok, _guardrail_modules} -> {:cont, {:ok, spec_acc}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
    end
  end

  defp format_model_error(reason) when is_binary(reason), do: reason

  defp format_model_error(%{message: message}) when is_binary(message),
    do: message

  defp format_model_error(reason), do: inspect(reason)

  defp hooks_unique?(hooks) do
    Enum.all?(hooks, fn {_stage, hook_names} -> Enum.uniq(hook_names) == hook_names end)
  end

  defp hooks_empty?(hooks) do
    Enum.all?(hooks, fn {_stage, hook_names} -> hook_names == [] end)
  end

  defp guardrails_unique?(guardrails) do
    Enum.all?(guardrails, fn {_stage, guardrail_names} ->
      Enum.uniq(guardrail_names) == guardrail_names
    end)
  end

  defp guardrails_empty?(guardrails) do
    Enum.all?(guardrails, fn {_stage, guardrail_names} -> guardrail_names == [] end)
  end

  defp subagents_unique?(subagents) do
    names =
      Enum.map(subagents, fn subagent ->
        Map.get(subagent, :as) || Map.fetch!(subagent, :agent)
      end)

    Enum.uniq(names) == names
  end

  defp imported_subagent_target(%{target: "ephemeral"}), do: :ephemeral

  defp imported_subagent_target(%{target: "peer", peer_id: peer_id})
       when is_binary(peer_id) and peer_id != "" do
    {:peer, peer_id}
  end

  defp imported_subagent_target(%{target: "peer", peer_id_context_key: key})
       when (is_binary(key) and key != "") or is_atom(key) do
    {:peer, {:context, key}}
  end

  defp imported_subagent_target(%{target: target}) do
    target
  end

  defp format_zoi_errors(errors) do
    errors
    |> Zoi.treefy_errors()
    |> inspect(pretty: true)
  end
end
