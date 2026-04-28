defmodule Jidoka.ImportedAgent.Spec do
  @moduledoc false

  @id_schema [
    Zoi.string()
    |> Zoi.trim()
    |> Zoi.min(1)
    |> Zoi.max(64)
    |> Zoi.regex(~r/^[a-z][a-z0-9_]*$/)
  ]

  @instructions_schema [
    Zoi.string()
    |> Zoi.min(1)
    |> Zoi.max(50_000)
  ]

  @character_name_schema Zoi.string()
                         |> Zoi.trim()
                         |> Zoi.min(1)
                         |> Zoi.max(128)

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

  @workflow_name_schema Zoi.string()
                        |> Zoi.trim()
                        |> Zoi.min(1)
                        |> Zoi.max(128)
                        |> Zoi.regex(~r/^[a-z][a-z0-9_]*$/)

  @workflow_tool_name_schema Zoi.string()
                             |> Zoi.trim()
                             |> Zoi.min(1)
                             |> Zoi.max(128)
                             |> Zoi.regex(~r/^[a-z][a-z0-9_]*$/)

  @handoff_agent_name_schema @subagent_agent_name_schema
  @handoff_tool_name_schema @subagent_tool_name_schema

  @web_mode_schema Zoi.string()
                   |> Zoi.trim()
                   |> Zoi.min(1)

  @subagent_forward_context_key_schema Zoi.union([
                                         Zoi.string() |> Zoi.trim() |> Zoi.min(1),
                                         Zoi.atom()
                                       ])

  @subagent_forward_context_schema Zoi.union([
                                     Zoi.string() |> Zoi.trim() |> Zoi.min(1),
                                     Zoi.object(
                                       %{
                                         mode:
                                           Zoi.string()
                                           |> Zoi.trim()
                                           |> Zoi.min(1),
                                         keys:
                                           Zoi.list(@subagent_forward_context_key_schema)
                                           |> Zoi.optional()
                                       },
                                       coerce: true,
                                       unrecognized_keys: :error
                                     )
                                   ])

  @workflow_forward_context_schema @subagent_forward_context_schema
  @handoff_forward_context_schema @subagent_forward_context_schema

  @hook_name_schema Zoi.string()
                    |> Zoi.trim()
                    |> Zoi.min(1)
                    |> Zoi.max(128)
                    |> Zoi.regex(~r/^[a-z][a-z0-9_]*$/)

  @skill_name_schema Zoi.string()
                     |> Zoi.trim()
                     |> Zoi.min(1)
                     |> Zoi.max(128)
                     |> Zoi.regex(~r/^[a-z0-9]+(-[a-z0-9]+)*$/)

  @skill_path_schema Zoi.string()
                     |> Zoi.trim()
                     |> Zoi.min(1)
                     |> Zoi.max(4_096)

  @mcp_endpoint_schema Zoi.string()
                       |> Zoi.trim()
                       |> Zoi.min(1)
                       |> Zoi.max(128)

  @guardrail_name_schema Zoi.string()
                         |> Zoi.trim()
                         |> Zoi.min(1)
                         |> Zoi.max(128)
                         |> Zoi.regex(~r/^[a-z][a-z0-9_]*$/)

  @default_hooks %{before_turn: [], after_turn: [], on_interrupt: []}
  @default_guardrails %{input: [], output: [], tool: []}
  @default_memory nil
  @default_subagents []
  @default_workflows []
  @default_handoffs []
  @default_web []
  @default_skills []
  @default_skill_paths []
  @default_mcp_tools []
  @default_output nil

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
                         |> Zoi.optional(),
                       timeout_ms: Zoi.integer() |> Zoi.optional(),
                       forward_context: @subagent_forward_context_schema |> Zoi.optional(),
                       result:
                         Zoi.string()
                         |> Zoi.trim()
                         |> Zoi.min(1)
                         |> Zoi.optional()
                     },
                     coerce: true,
                     unrecognized_keys: :error
                   )

  @workflow_schema Zoi.union([
                     @workflow_name_schema,
                     Zoi.object(
                       %{
                         workflow: @workflow_name_schema,
                         as: @workflow_tool_name_schema |> Zoi.optional(),
                         description:
                           Zoi.string()
                           |> Zoi.trim()
                           |> Zoi.min(1)
                           |> Zoi.max(1_000)
                           |> Zoi.optional(),
                         timeout: Zoi.integer() |> Zoi.optional(),
                         forward_context: @workflow_forward_context_schema |> Zoi.optional(),
                         result:
                           Zoi.string()
                           |> Zoi.trim()
                           |> Zoi.min(1)
                           |> Zoi.optional()
                       },
                       coerce: true,
                       unrecognized_keys: :error
                     )
                   ])

  @handoff_schema Zoi.union([
                    @handoff_agent_name_schema,
                    Zoi.object(
                      %{
                        agent: @handoff_agent_name_schema,
                        as: @handoff_tool_name_schema |> Zoi.optional(),
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
                          |> Zoi.default("auto"),
                        peer_id:
                          Zoi.string()
                          |> Zoi.trim()
                          |> Zoi.min(1)
                          |> Zoi.optional(),
                        peer_id_context_key:
                          Zoi.union([Zoi.string() |> Zoi.trim() |> Zoi.min(1), Zoi.atom()])
                          |> Zoi.optional(),
                        forward_context: @handoff_forward_context_schema |> Zoi.optional()
                      },
                      coerce: true,
                      unrecognized_keys: :error
                    )
                  ])

  @web_schema Zoi.union([
                @web_mode_schema,
                Zoi.object(
                  %{
                    mode: @web_mode_schema
                  },
                  coerce: true,
                  unrecognized_keys: :error
                )
              ])

  @guardrails_schema Zoi.object(
                       %{
                         input: Zoi.list(@guardrail_name_schema) |> Zoi.default([]),
                         output: Zoi.list(@guardrail_name_schema) |> Zoi.default([]),
                         tool: Zoi.list(@guardrail_name_schema) |> Zoi.default([])
                       },
                       coerce: true,
                       unrecognized_keys: :error
                     )

  @mcp_tool_schema Zoi.object(
                     %{
                       endpoint: @mcp_endpoint_schema,
                       prefix:
                         Zoi.string()
                         |> Zoi.trim()
                         |> Zoi.min(1)
                         |> Zoi.max(128)
                         |> Zoi.optional()
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
                       |> Zoi.default("instructions")
                   },
                   coerce: true,
                   unrecognized_keys: :error
                 )

  @model_schema Zoi.union([
                  Zoi.string() |> Zoi.trim() |> Zoi.min(1) |> Zoi.max(256),
                  @model_map_schema
                ])

  @output_schema Zoi.object(
                   %{
                     schema: Zoi.map(),
                     retries: Zoi.integer() |> Zoi.default(1),
                     on_validation_error:
                       Zoi.string()
                       |> Zoi.trim()
                       |> Zoi.min(1)
                       |> Zoi.default("repair")
                   },
                   coerce: true,
                   unrecognized_keys: :error
                 )

  @agent_schema Zoi.object(
                  %{
                    id: hd(@id_schema),
                    description:
                      Zoi.string()
                      |> Zoi.trim()
                      |> Zoi.min(1)
                      |> Zoi.max(1_000)
                      |> Zoi.optional(),
                    context: Zoi.map() |> Zoi.default(%{})
                  },
                  coerce: true,
                  unrecognized_keys: :error
                )

  @defaults_schema Zoi.object(
                     %{
                       model: @model_schema |> Zoi.default("fast"),
                       instructions: hd(@instructions_schema),
                       character: Zoi.union([@character_name_schema, Zoi.map()]) |> Zoi.optional()
                     },
                     coerce: true,
                     unrecognized_keys: :error
                   )

  @capabilities_schema Zoi.object(
                         %{
                           tools: Zoi.list(@tool_name_schema) |> Zoi.default([]),
                           skills: Zoi.list(@skill_name_schema) |> Zoi.default(@default_skills),
                           skill_paths: Zoi.list(@skill_path_schema) |> Zoi.default(@default_skill_paths),
                           mcp_tools: Zoi.list(@mcp_tool_schema) |> Zoi.default(@default_mcp_tools),
                           subagents: Zoi.list(@subagent_schema) |> Zoi.default(@default_subagents),
                           workflows: Zoi.list(@workflow_schema) |> Zoi.default(@default_workflows),
                           handoffs: Zoi.list(@handoff_schema) |> Zoi.default(@default_handoffs),
                           web: Zoi.list(@web_schema) |> Zoi.default(@default_web),
                           plugins: Zoi.list(@plugin_name_schema) |> Zoi.default([])
                         },
                         coerce: true,
                         unrecognized_keys: :error
                       )

  @lifecycle_schema Zoi.object(
                      %{
                        memory: Zoi.union([@memory_schema, Zoi.literal(nil)]) |> Zoi.default(nil),
                        hooks: @hooks_schema |> Zoi.default(@default_hooks),
                        guardrails: @guardrails_schema |> Zoi.default(@default_guardrails)
                      },
                      coerce: true,
                      unrecognized_keys: :error
                    )

  @schema Zoi.object(
            %{
              agent: @agent_schema,
              defaults: @defaults_schema,
              capabilities: @capabilities_schema |> Zoi.default(%{}),
              lifecycle: @lifecycle_schema |> Zoi.default(%{}),
              output: Zoi.union([@output_schema, Zoi.literal(nil)]) |> Zoi.default(nil)
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
          id: String.t(),
          description: String.t() | nil,
          instructions: String.t(),
          character: String.t() | map() | nil,
          model: model_input(),
          context: map(),
          output: Jidoka.Output.t() | nil,
          memory: Jidoka.Memory.config() | nil,
          tools: [String.t()],
          skills: [String.t()],
          skill_paths: [String.t()],
          mcp_tools: [map()],
          subagents: [map()],
          workflows: [String.t() | map()],
          handoffs: [String.t() | map()],
          web: [String.t() | map()],
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

  @enforce_keys [:id, :instructions, :model]
  defstruct [
    :id,
    :description,
    :instructions,
    :character,
    :model,
    context: %{},
    output: @default_output,
    memory: @default_memory,
    tools: [],
    skills: @default_skills,
    skill_paths: @default_skill_paths,
    mcp_tools: @default_mcp_tools,
    subagents: @default_subagents,
    workflows: @default_workflows,
    handoffs: @default_handoffs,
    web: @default_web,
    plugins: [],
    hooks: @default_hooks,
    guardrails: @default_guardrails
  ]

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec new(map() | t(), keyword()) :: {:ok, t()} | {:error, term()}
  def new(%__MODULE__{} = spec, opts) do
    with :ok <- validate_context(spec.context),
         {:ok, normalized_output} <- normalize_output(spec.output),
         {:ok, normalized_memory} <- Jidoka.Memory.normalize_imported(spec.memory),
         {:ok, _character_spec} <- validate_character(spec.character, Keyword.get(opts, :available_characters, %{})),
         {:ok, normalized_skills} <- Jidoka.Skill.normalize_imported(spec.skills, spec.skill_paths),
         {:ok, normalized_mcp_tools} <- Jidoka.MCP.normalize_imported(spec.mcp_tools),
         {:ok, spec} <- validate_tools(spec, Keyword.get(opts, :available_tools, %{})),
         {:ok, spec} <- validate_skills(spec, Keyword.get(opts, :available_skills, %{})),
         {:ok, spec} <- validate_subagents(spec, Keyword.get(opts, :available_subagents, %{})),
         {:ok, spec} <- validate_workflows(spec, Keyword.get(opts, :available_workflows, %{})),
         {:ok, spec} <- validate_handoffs(spec, Keyword.get(opts, :available_handoffs, %{})),
         {:ok, spec} <- validate_web(spec),
         {:ok, spec} <- validate_plugins(spec, Keyword.get(opts, :available_plugins, %{})),
         {:ok, spec} <- validate_hooks(spec, Keyword.get(opts, :available_hooks, %{})) do
      validate_guardrails(
        %{
          spec
          | memory: normalized_memory,
            output: normalized_output,
            skills: (normalized_skills && normalized_skills.refs) || [],
            skill_paths: (normalized_skills && normalized_skills.load_paths) || [],
            mcp_tools: normalized_mcp_tools
        },
        Keyword.get(opts, :available_guardrails, %{})
      )
    end
  end

  def new(attrs, opts) when is_map(attrs) do
    with {:ok, parsed} <- Zoi.parse(@schema, attrs),
         spec <- from_external(parsed),
         {:ok, normalized_model} <- normalize_model(spec.model),
         :ok <- validate_model(normalized_model),
         :ok <- validate_context(spec.context),
         {:ok, normalized_output} <- normalize_output(spec.output),
         {:ok, normalized_memory} <- Jidoka.Memory.normalize_imported(spec.memory),
         {:ok, _character_spec} <- validate_character(spec.character, Keyword.get(opts, :available_characters, %{})),
         {:ok, normalized_skills} <- Jidoka.Skill.normalize_imported(spec.skills, spec.skill_paths),
         {:ok, normalized_mcp_tools} <- Jidoka.MCP.normalize_imported(spec.mcp_tools),
         {:ok, normalized_spec} <-
           validate_tools(
             %{
               spec
               | model: normalized_model,
                 output: normalized_output,
                 memory: normalized_memory,
                 skills: (normalized_skills && normalized_skills.refs) || [],
                 skill_paths: (normalized_skills && normalized_skills.load_paths) || [],
                 mcp_tools: normalized_mcp_tools
             },
             Keyword.get(opts, :available_tools, %{})
           ),
         {:ok, normalized_spec} <-
           validate_skills(
             normalized_spec,
             Keyword.get(opts, :available_skills, %{})
           ),
         {:ok, normalized_spec} <-
           validate_subagents(
             normalized_spec,
             Keyword.get(opts, :available_subagents, %{})
           ),
         {:ok, normalized_spec} <-
           validate_workflows(
             normalized_spec,
             Keyword.get(opts, :available_workflows, %{})
           ),
         {:ok, normalized_spec} <-
           validate_handoffs(
             normalized_spec,
             Keyword.get(opts, :available_handoffs, %{})
           ),
         {:ok, normalized_spec} <- validate_web(normalized_spec),
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
    do: {:error, "imported Jidoka agent specs must be maps, got: #{inspect(other)}"}

  @spec to_external_map(t()) :: map()
  def to_external_map(%__MODULE__{} = spec) do
    %{
      "agent" =>
        %{
          "id" => spec.id,
          "description" => spec.description,
          "context" => spec.context
        }
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Map.new(),
      "defaults" =>
        %{
          "model" => externalize_model(spec.model),
          "instructions" => spec.instructions,
          "character" => spec.character
        }
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Map.new(),
      "capabilities" => %{
        "tools" => spec.tools,
        "skills" => spec.skills,
        "skill_paths" => spec.skill_paths,
        "mcp_tools" => spec.mcp_tools,
        "subagents" => spec.subagents,
        "workflows" => spec.workflows,
        "handoffs" => spec.handoffs,
        "web" => spec.web,
        "plugins" => spec.plugins
      },
      "lifecycle" => %{
        "memory" => externalize_memory(spec.memory),
        "hooks" => spec.hooks,
        "guardrails" => spec.guardrails
      },
      "output" => externalize_output(spec.output)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  @spec fingerprint(t()) :: String.t()
  def fingerprint(%__MODULE__{} = spec) do
    spec
    |> to_external_map()
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp from_external(%{} = attrs) do
    agent = Map.fetch!(attrs, :agent)
    defaults = Map.fetch!(attrs, :defaults)
    capabilities = Map.get(attrs, :capabilities, %{})
    lifecycle = Map.get(attrs, :lifecycle, %{})

    %__MODULE__{
      id: Map.fetch!(agent, :id),
      description: Map.get(agent, :description),
      instructions: Map.fetch!(defaults, :instructions),
      character: Map.get(defaults, :character),
      model: Map.get(defaults, :model, "fast"),
      context: Map.get(agent, :context, %{}),
      output: Map.get(attrs, :output, @default_output),
      memory: Map.get(lifecycle, :memory),
      tools: Map.get(capabilities, :tools, []),
      skills: Map.get(capabilities, :skills, @default_skills),
      skill_paths: Map.get(capabilities, :skill_paths, @default_skill_paths),
      mcp_tools: Map.get(capabilities, :mcp_tools, @default_mcp_tools),
      subagents: Map.get(capabilities, :subagents, @default_subagents),
      workflows: normalize_workflow_specs(Map.get(capabilities, :workflows, @default_workflows)),
      handoffs: normalize_handoff_specs(Map.get(capabilities, :handoffs, @default_handoffs)),
      web: Jidoka.Web.normalize_imported_specs(Map.get(capabilities, :web, @default_web)),
      plugins: Map.get(capabilities, :plugins, []),
      hooks: Map.get(lifecycle, :hooks, @default_hooks),
      guardrails: Map.get(lifecycle, :guardrails, @default_guardrails)
    }
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
            {:error, "model must be a known alias string like \"fast\" or a direct provider:model string"}
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
    |> Jidoka.model()
    |> ReqLLM.model()
    |> case do
      {:ok, _model} -> :ok
      {:error, reason} -> {:error, format_model_error(reason)}
    end
  end

  defp validate_context(context) do
    case Jidoka.Context.validate_default(context) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_output(nil), do: {:ok, nil}

  defp normalize_output(%Jidoka.Output{} = output), do: {:ok, output}

  defp normalize_output(%{} = output) do
    case Jidoka.Output.new(output) do
      {:ok, %Jidoka.Output{schema_kind: :json_schema} = normalized} ->
        {:ok, normalized}

      {:ok, %Jidoka.Output{schema_kind: :zoi}} ->
        {:error, "imported output schema must be an object-shaped JSON Schema map"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_output(other),
    do: {:error, "output must be a map with an object-shaped JSON Schema, got: #{inspect(other)}"}

  defp validate_character(nil, _available_characters), do: {:ok, nil}

  defp validate_character(character, _available_characters) when is_map(character) do
    Jidoka.Character.normalize(nil, character, label: "character")
  end

  defp validate_character(character, available_characters) when is_binary(character) and is_map(available_characters) do
    cond do
      map_size(available_characters) == 0 ->
        {:error, "character refs require an available_characters registry when importing Jidoka agents"}

      true ->
        with {:ok, source} <- Jidoka.Character.resolve_character_name(character, available_characters) do
          Jidoka.Character.normalize(nil, source, label: "character #{inspect(character)}")
        end
    end
  end

  defp validate_character(character, _available_characters) do
    {:error, "character must be an inline map or a string ref, got: #{inspect(character)}"}
  end

  defp alias_atom(name) do
    (Map.keys(Jidoka.model_aliases()) ++ Map.keys(Jido.AI.model_aliases()))
    |> Enum.uniq()
    |> Enum.find_value(:error, fn alias_name ->
      if Atom.to_string(alias_name) == name, do: {:ok, alias_name}, else: false
    end)
  end

  defp externalize_model(model) when is_atom(model), do: Atom.to_string(model)
  defp externalize_model(model), do: model

  defp externalize_output(nil), do: nil

  defp externalize_output(%Jidoka.Output{} = output) do
    %{
      "schema" => output.schema,
      "retries" => output.retries,
      "on_validation_error" => Atom.to_string(output.on_validation_error)
    }
  end

  defp externalize_output(%{} = output), do: output

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
        {:error, "tools require an available_tools registry when importing Jidoka agents"}

      true ->
        case Jidoka.Tool.resolve_tool_names(spec.tools, available_tools) do
          {:ok, _tool_modules} -> {:ok, spec}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp validate_skills(%__MODULE__{} = spec, available_skills) when is_map(available_skills) do
    cond do
      Enum.uniq(spec.skills) != spec.skills ->
        {:error, "skills must be unique"}

      spec.skills == [] ->
        {:ok, spec}

      true ->
        case Jidoka.Skill.resolve_skill_refs(spec.skills, available_skills) do
          {:ok, _skill_refs} -> {:ok, spec}
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
        {:error, "plugins require an available_plugins registry when importing Jidoka agents"}

      true ->
        case Jidoka.Plugin.resolve_plugin_names(spec.plugins, available_plugins) do
          {:ok, _plugin_modules} -> {:ok, spec}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp validate_web(%__MODULE__{} = spec) do
    case Jidoka.Web.normalize_imported(spec.web) do
      {:ok, _web} -> {:ok, spec}
      {:error, reason} -> {:error, reason}
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
        {:error, "subagents require an available_subagents registry when importing Jidoka agents"}

      true ->
        spec.subagents
        |> Enum.reduce_while({:ok, spec}, fn subagent, {:ok, spec_acc} ->
          with {:ok, agent_module} <-
                 Jidoka.Subagent.resolve_subagent_name(subagent.agent, available_subagents),
               {:ok, _normalized} <-
                 Jidoka.Subagent.new(
                   agent_module,
                   as: Map.get(subagent, :as),
                   description: Map.get(subagent, :description),
                   target: imported_subagent_target(subagent),
                   timeout: Map.get(subagent, :timeout_ms, 30_000),
                   forward_context: Map.get(subagent, :forward_context, :public),
                   result: Map.get(subagent, :result, :text)
                 ) do
            {:cont, {:ok, spec_acc}}
          else
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
    end
  end

  defp validate_workflows(%__MODULE__{} = spec, available_workflows)
       when is_map(available_workflows) do
    cond do
      not workflows_unique?(spec.workflows) ->
        {:error, "workflow capability names must be unique"}

      spec.workflows == [] ->
        {:ok, spec}

      map_size(available_workflows) == 0 ->
        {:error, "workflows require an available_workflows registry when importing Jidoka agents"}

      true ->
        spec.workflows
        |> Enum.reduce_while({:ok, spec}, fn workflow, {:ok, spec_acc} ->
          with {:ok, workflow_module} <-
                 Jidoka.Workflow.Capability.resolve_workflow_name(workflow.workflow, available_workflows),
               {:ok, _normalized} <-
                 Jidoka.Workflow.Capability.new(
                   workflow_module,
                   as: Map.get(workflow, :as),
                   description: Map.get(workflow, :description),
                   timeout: Map.get(workflow, :timeout, 30_000),
                   forward_context: Map.get(workflow, :forward_context, :public),
                   result: Map.get(workflow, :result, :output)
                 ) do
            {:cont, {:ok, spec_acc}}
          else
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
    end
  end

  defp validate_handoffs(%__MODULE__{} = spec, available_handoffs)
       when is_map(available_handoffs) do
    cond do
      not handoffs_unique?(spec.handoffs) ->
        {:error, "handoff names must be unique"}

      spec.handoffs == [] ->
        {:ok, spec}

      map_size(available_handoffs) == 0 ->
        {:error, "handoffs require an available_handoffs registry when importing Jidoka agents"}

      true ->
        spec.handoffs
        |> Enum.reduce_while({:ok, spec}, fn handoff, {:ok, spec_acc} ->
          with {:ok, agent_module} <-
                 Jidoka.Handoff.Capability.resolve_handoff_name(handoff.agent, available_handoffs),
               {:ok, _normalized} <-
                 Jidoka.Handoff.Capability.new(
                   agent_module,
                   as: Map.get(handoff, :as),
                   description: Map.get(handoff, :description),
                   target: imported_handoff_target(handoff),
                   forward_context: Map.get(handoff, :forward_context, :public)
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
        {:error, "hooks require an available_hooks registry when importing Jidoka agents"}

      true ->
        spec.hooks
        |> Enum.reduce_while({:ok, spec}, fn {_stage, hook_names}, {:ok, spec_acc} ->
          case Jidoka.Hook.resolve_hook_names(hook_names, available_hooks) do
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
        {:error, "guardrails require an available_guardrails registry when importing Jidoka agents"}

      true ->
        spec.guardrails
        |> Enum.reduce_while({:ok, spec}, fn {_stage, guardrail_names}, {:ok, spec_acc} ->
          case Jidoka.Guardrail.resolve_guardrail_names(guardrail_names, available_guardrails) do
            {:ok, _guardrail_modules} -> {:cont, {:ok, spec_acc}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
    end
  end

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

  defp workflows_unique?(workflows) do
    names =
      Enum.map(workflows, fn workflow ->
        Map.get(workflow, :as) || Map.fetch!(workflow, :workflow)
      end)

    Enum.uniq(names) == names
  end

  defp handoffs_unique?(handoffs) do
    names =
      Enum.map(handoffs, fn handoff ->
        Map.get(handoff, :as) || Map.fetch!(handoff, :agent)
      end)

    Enum.uniq(names) == names
  end

  defp normalize_workflow_specs(workflows) when is_list(workflows) do
    Enum.map(workflows, fn
      workflow when is_binary(workflow) -> %{workflow: workflow}
      %{} = workflow -> workflow
    end)
  end

  defp normalize_handoff_specs(handoffs) when is_list(handoffs) do
    Enum.map(handoffs, fn
      handoff when is_binary(handoff) -> %{agent: handoff}
      %{} = handoff -> handoff
    end)
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

  defp imported_handoff_target(%{target: "auto"}), do: :auto

  defp imported_handoff_target(%{target: "peer", peer_id: peer_id})
       when is_binary(peer_id) and peer_id != "" do
    {:peer, peer_id}
  end

  defp imported_handoff_target(%{target: "peer", peer_id_context_key: key})
       when (is_binary(key) and key != "") or is_atom(key) do
    {:peer, {:context, key}}
  end

  defp imported_handoff_target(%{target: target}) do
    target
  end

  defp imported_handoff_target(%{agent: _agent}), do: :auto

  defp format_zoi_errors(errors) do
    errors
    |> Zoi.treefy_errors()
    |> inspect(pretty: true)
  end
end
