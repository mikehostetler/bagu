defmodule Moto.DynamicAgent do
  @moduledoc false

  alias Moto.DynamicAgent.Spec

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
          spec: Spec.t(),
          runtime_module: module(),
          tool_modules: [module()],
          subagents: [Moto.Subagent.t()],
          plugin_modules: [module()],
          hook_modules: Moto.Hooks.stage_map(),
          guardrail_modules: Moto.Guardrails.stage_map()
        }

  @spec import(map() | binary() | Spec.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def import(source, opts \\ [])

  def import(%Spec{} = spec, opts) do
    with_registries(opts, fn registries ->
      build_from_source(spec, registries)
    end)
  end

  def import(source, opts) when is_map(source) do
    with_registries(opts, fn registries ->
      build_from_source(source, registries)
    end)
  end

  def import(source, opts) when is_binary(source) do
    with {:ok, attrs} <- decode(source, Keyword.get(opts, :format, :auto)) do
      with_registries(opts, fn registries ->
        build_from_source(attrs, registries)
      end)
    end
  end

  def import(other, _opts),
    do: {:error, "cannot import Moto agent from #{inspect(other)}"}

  @spec import_file(Path.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def import_file(path, opts \\ []) when is_binary(path) do
    with {:ok, contents} <- File.read(path),
         {:ok, format} <- detect_file_format(path, Keyword.get(opts, :format)),
         {:ok, agent} <- __MODULE__.import(contents, Keyword.put(opts, :format, format)) do
      {:ok, agent}
    else
      {:error, :enoent} ->
        {:error, "could not read agent spec file: #{path}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec start_link(t(), keyword()) :: DynamicSupervisor.on_start_child()
  def start_link(%__MODULE__{runtime_module: runtime_module}, opts \\ []) do
    Moto.Runtime.start_agent(runtime_module, opts)
  end

  @spec encode(t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def encode(%__MODULE__{spec: spec}, opts \\ []) do
    case Keyword.get(opts, :format, :json) do
      :json ->
        {:ok, Jason.encode!(Spec.to_external_map(spec), pretty: true)}

      :yaml ->
        {:ok, encode_yaml(spec)}

      other ->
        {:error, "unsupported format #{inspect(other)}; expected :json or :yaml"}
    end
  end

  @spec format_error(term()) :: String.t()
  def format_error(reason) when is_binary(reason), do: reason
  def format_error(%{message: message}) when is_binary(message), do: message
  def format_error(reason), do: inspect(reason)

  defp build(
         %Spec{} = spec,
         tool_registry,
         subagent_registry,
         plugin_registry,
         hook_registry,
         guardrail_registry
       ) do
    with {:ok, direct_tool_modules} <- Moto.Tool.resolve_tool_names(spec.tools, tool_registry),
         {:ok, resolved_subagents} <-
           resolve_imported_subagents(spec.subagents, subagent_registry),
         {:ok, plugin_modules} <- Moto.Plugin.resolve_plugin_names(spec.plugins, plugin_registry),
         {:ok, plugin_tool_modules} <- Moto.Plugin.plugin_actions(plugin_modules),
         {:ok, direct_tool_names} <-
           Moto.Tool.action_names(direct_tool_modules ++ plugin_tool_modules),
         subagent_tool_modules <-
           resolved_subagents
           |> Enum.with_index()
           |> Enum.map(fn {subagent, index} ->
             Moto.Subagent.tool_module(generated_module_base(spec), subagent, index)
           end),
         {:ok, hook_modules} <- resolve_imported_hooks(spec.hooks, hook_registry),
         {:ok, guardrail_modules} <-
           resolve_imported_guardrails(spec.guardrails, guardrail_registry),
         tool_modules = direct_tool_modules ++ plugin_tool_modules ++ subagent_tool_modules,
         :ok <-
           ensure_unique_tool_names(direct_tool_names ++ Enum.map(resolved_subagents, & &1.name)),
         {:ok, runtime_module} <-
           ensure_runtime_module(
             spec,
             tool_modules,
             resolved_subagents,
             plugin_modules,
             hook_modules,
             guardrail_modules
           ) do
      {:ok,
       %__MODULE__{
         spec: spec,
         runtime_module: runtime_module,
         tool_modules: tool_modules,
         subagents: resolved_subagents,
         plugin_modules: plugin_modules,
         hook_modules: hook_modules,
         guardrail_modules: guardrail_modules
       }}
    end
  end

  defp ensure_unique_tool_names(tool_names) do
    if Enum.uniq(tool_names) == tool_names do
      :ok
    else
      duplicates =
        tool_names
        |> Enum.frequencies()
        |> Enum.filter(fn {_name, count} -> count > 1 end)
        |> Enum.map(&elem(&1, 0))
        |> Enum.sort()

      {:error, "duplicate tool names in imported Moto agent: #{Enum.join(duplicates, ", ")}"}
    end
  end

  defp decode(source, :auto) do
    source
    |> detect_source_format()
    |> then(&decode(source, &1))
  end

  defp decode(source, :json) do
    case Jason.decode(source) do
      {:ok, %{} = attrs} ->
        {:ok, attrs}

      {:ok, other} ->
        {:error, "dynamic Moto agent specs must decode to an object, got: #{inspect(other)}"}

      {:error, error} ->
        {:error, Exception.message(error)}
    end
  end

  defp decode(source, :yaml) do
    case YamlElixir.read_from_string(source) do
      {:ok, %{} = attrs} ->
        {:ok, attrs}

      {:ok, other} ->
        {:error, "dynamic Moto agent specs must decode to a map, got: #{inspect(other)}"}

      {:error, error} ->
        {:error, format_error(error)}
    end
  end

  defp decode(_source, format),
    do: {:error, "unsupported format #{inspect(format)}; expected :json, :yaml, or :auto"}

  defp detect_source_format(source) do
    case String.trim_leading(source) do
      <<"{"::utf8, _::binary>> -> :json
      _ -> :yaml
    end
  end

  defp detect_file_format(_path, format) when format in [:json, :yaml], do: {:ok, format}

  defp detect_file_format(path, nil) do
    case Path.extname(path) do
      ".json" ->
        {:ok, :json}

      ".yaml" ->
        {:ok, :yaml}

      ".yml" ->
        {:ok, :yaml}

      ext ->
        {:error,
         "unsupported agent spec extension #{inspect(ext)}; expected .json, .yaml, or .yml"}
    end
  end

  defp detect_file_format(_path, other),
    do: {:error, "unsupported format #{inspect(other)}; expected :json or :yaml"}

  defp ensure_runtime_module(
         %Spec{} = spec,
         tool_modules,
         subagents,
         plugin_modules,
         hook_modules,
         guardrail_modules
       ) do
    runtime_plugins = runtime_plugins(plugin_modules, spec.memory)

    runtime_module =
      generated_module(
        spec,
        tool_modules,
        subagents,
        runtime_plugins,
        hook_modules,
        guardrail_modules
      )

    if Code.ensure_loaded?(runtime_module) do
      {:ok, runtime_module}
    else
      create_runtime_module(
        runtime_module,
        spec,
        tool_modules,
        subagents,
        runtime_plugins,
        hook_modules,
        guardrail_modules
      )
    end
  end

  defp generated_module(
         %Spec{} = spec,
         tool_modules,
         subagents,
         runtime_plugins,
         hook_modules,
         guardrail_modules
       ) do
    suffix =
      %{
        spec: Spec.to_external_map(spec),
        tools: Enum.map(tool_modules, &inspect/1),
        subagents:
          Enum.map(subagents, fn subagent ->
            %{
              name: subagent.name,
              agent: inspect(subagent.agent),
              target: externalize_subagent_target(subagent.target)
            }
          end),
        plugins: Enum.map(runtime_plugins, &inspect/1),
        hooks:
          Enum.into(hook_modules, %{}, fn {stage, modules} ->
            {stage, Enum.map(modules, &inspect/1)}
          end),
        guardrails:
          Enum.into(guardrail_modules, %{}, fn {stage, modules} ->
            {stage, Enum.map(modules, &inspect/1)}
          end)
      }
      |> Jason.encode!()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)
      |> String.slice(0, 16)
      |> String.upcase()

    Module.concat([__MODULE__, Generated, "Runtime#{suffix}"])
  end

  defp create_runtime_module(
         runtime_module,
         %Spec{} = spec,
         tool_modules,
         subagents,
         runtime_plugins,
         hook_modules,
         guardrail_modules
       ) do
    request_transformer_module = Module.concat(runtime_module, RequestTransformer)

    effective_request_transformer =
      if Moto.Memory.requires_request_transformer?(spec.memory) do
        request_transformer_module
      else
        nil
      end

    generated_tool_modules =
      subagents
      |> Enum.with_index()
      |> Enum.map(fn {subagent, index} ->
        tool_module = Moto.Subagent.tool_module(generated_module_base(spec), subagent, index)
        Moto.Subagent.tool_module_ast(tool_module, subagent)
      end)

    quoted =
      quote location: :keep do
        if unquote(Macro.escape(effective_request_transformer)) do
          defmodule unquote(request_transformer_module) do
            @moduledoc false
            @behaviour Jido.AI.Reasoning.ReAct.RequestTransformer

            @system_prompt_spec unquote(Macro.escape(spec.system_prompt))

            @impl true
            def transform_request(request, state, config, runtime_context) do
              Moto.Agent.RequestTransformer.transform_request(
                @system_prompt_spec,
                request,
                state,
                config,
                runtime_context
              )
            end
          end
        end

        unquote_splicing(generated_tool_modules)

        use Jido.AI.Agent,
          name: unquote(spec.name),
          system_prompt: unquote(spec.system_prompt),
          model: unquote(Macro.escape(spec.model)),
          tools: unquote(Macro.escape(tool_modules)),
          plugins: unquote(Macro.escape(runtime_plugins)),
          default_plugins: %{__memory__: false},
          request_transformer: unquote(Macro.escape(effective_request_transformer))

        unquote(
          Moto.Agent.hook_runtime_ast(hook_modules, spec.context, guardrail_modules, spec.memory)
        )
      end

    case Module.create(runtime_module, quoted, Macro.Env.location(__ENV__)) do
      {:module, ^runtime_module, _binary, _term} ->
        {:ok, runtime_module}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error in [ArgumentError] ->
      if Code.ensure_loaded?(runtime_module) do
        {:ok, runtime_module}
      else
        {:error, error}
      end
  end

  defp available_tool_registry(opts) do
    opts
    |> Keyword.get(:available_tools, [])
    |> Moto.Tool.normalize_available_tools()
  end

  defp available_plugin_registry(opts) do
    opts
    |> Keyword.get(:available_plugins, [])
    |> Moto.Plugin.normalize_available_plugins()
  end

  defp available_subagent_registry(opts) do
    opts
    |> Keyword.get(:available_subagents, [])
    |> Moto.Subagent.normalize_available_subagents()
  end

  defp available_hook_registry(opts) do
    opts
    |> Keyword.get(:available_hooks, [])
    |> Moto.Hook.normalize_available_hooks()
  end

  defp available_guardrail_registry(opts) do
    opts
    |> Keyword.get(:available_guardrails, [])
    |> Moto.Guardrail.normalize_available_guardrails()
  end

  defp resolve_imported_hooks(hooks, hook_registry) do
    hooks
    |> Enum.reduce_while({:ok, Moto.Hooks.default_stage_map()}, fn {stage, hook_names},
                                                                   {:ok, acc} ->
      case Moto.Hook.resolve_hook_names(hook_names, hook_registry) do
        {:ok, modules} -> {:cont, {:ok, Map.put(acc, stage, modules)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp resolve_imported_guardrails(guardrails, guardrail_registry) do
    guardrails
    |> Enum.reduce_while({:ok, Moto.Guardrails.default_stage_map()}, fn {stage, guardrail_names},
                                                                        {:ok, acc} ->
      case Moto.Guardrail.resolve_guardrail_names(guardrail_names, guardrail_registry) do
        {:ok, modules} -> {:cont, {:ok, Map.put(acc, stage, modules)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp resolve_imported_subagents(subagents, subagent_registry) do
    subagents
    |> Enum.reduce_while({:ok, []}, fn subagent_spec, {:ok, acc} ->
      with {:ok, agent_module} <-
             Moto.Subagent.resolve_subagent_name(subagent_spec.agent, subagent_registry),
           {:ok, subagent} <-
             Moto.Subagent.new(
               agent_module,
               as: Map.get(subagent_spec, :as),
               description: Map.get(subagent_spec, :description),
               target: imported_subagent_target(subagent_spec)
             ) do
        {:cont, {:ok, acc ++ [subagent]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp imported_subagent_target(%{target: "ephemeral"}), do: :ephemeral
  defp imported_subagent_target(%{target: "peer", peer_id: peer_id}), do: {:peer, peer_id}

  defp imported_subagent_target(%{target: "peer", peer_id_context_key: key}),
    do: {:peer, {:context, key}}

  defp generated_module_base(%Spec{} = spec) do
    suffix =
      spec
      |> Spec.fingerprint()
      |> String.slice(0, 12)
      |> String.upcase()

    Module.concat([__MODULE__, Generated, "Runtime#{suffix}"])
  end

  defp externalize_subagent_target(:ephemeral), do: %{"target" => "ephemeral"}

  defp externalize_subagent_target({:peer, peer_id}) when is_binary(peer_id) do
    %{"target" => "peer", "peer_id" => peer_id}
  end

  defp externalize_subagent_target({:peer, {:context, key}}) do
    %{"target" => "peer", "peer_id_context_key" => to_string(key)}
  end

  defp runtime_plugins(plugin_modules, nil), do: [Moto.Plugins.RuntimeCompat | plugin_modules]

  defp runtime_plugins(plugin_modules, memory_config) do
    [Moto.Plugins.RuntimeCompat | plugin_modules] ++ [Moto.Memory.runtime_plugin(memory_config)]
  end

  defp with_registries(opts, fun) when is_list(opts) and is_function(fun, 1) do
    with {:ok, tool_registry} <- available_tool_registry(opts),
         {:ok, subagent_registry} <- available_subagent_registry(opts),
         {:ok, plugin_registry} <- available_plugin_registry(opts),
         {:ok, hook_registry} <- available_hook_registry(opts),
         {:ok, guardrail_registry} <- available_guardrail_registry(opts) do
      fun.(%{
        tools: tool_registry,
        subagents: subagent_registry,
        plugins: plugin_registry,
        hooks: hook_registry,
        guardrails: guardrail_registry
      })
    end
  end

  defp build_from_source(source, %{
         tools: tool_registry,
         subagents: subagent_registry,
         plugins: plugin_registry,
         hooks: hook_registry,
         guardrails: guardrail_registry
       }) do
    with {:ok, spec} <-
           Spec.new(source,
             available_tools: tool_registry,
             available_subagents: subagent_registry,
             available_plugins: plugin_registry,
             available_hooks: hook_registry,
             available_guardrails: guardrail_registry
           ) do
      build(
        spec,
        tool_registry,
        subagent_registry,
        plugin_registry,
        hook_registry,
        guardrail_registry
      )
    end
  end

  defp encode_yaml(%Spec{} = spec) do
    model_yaml =
      case Spec.to_external_map(spec)["model"] do
        model when is_binary(model) ->
          "model: #{Jason.encode!(model)}"

        %{} = model ->
          lines =
            model
            |> Enum.map(fn {key, value} -> "  #{key}: #{Jason.encode!(value)}" end)

          Enum.join(["model:" | lines], "\n")
      end

    prompt_block =
      spec.system_prompt
      |> String.split("\n", trim: false)
      |> Enum.map_join("\n", &"  #{&1}")

    [
      "name: #{Jason.encode!(spec.name)}",
      model_yaml,
      "system_prompt: |-",
      prompt_block,
      "context:",
      encode_yaml_context(spec.context),
      "memory:",
      encode_yaml_memory(spec.memory),
      "tools:",
      encode_yaml_tools(spec.tools),
      "subagents:",
      encode_yaml_subagents(spec.subagents),
      "plugins:",
      encode_yaml_plugins(spec.plugins),
      "hooks:",
      encode_yaml_hooks(spec.hooks),
      "guardrails:",
      encode_yaml_guardrails(spec.guardrails)
    ]
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  defp encode_yaml_tools([]), do: "  []"
  defp encode_yaml_tools(tools), do: Enum.map_join(tools, "\n", &"  - #{Jason.encode!(&1)}")

  defp encode_yaml_subagents([]), do: "  []"

  defp encode_yaml_subagents(subagents) do
    Enum.map_join(subagents, "\n", fn subagent ->
      lines =
        [
          "  - agent: #{Jason.encode!(subagent["agent"] || subagent[:agent])}"
        ] ++
          maybe_yaml_line("as", subagent["as"] || subagent[:as]) ++
          maybe_yaml_line("description", subagent["description"] || subagent[:description]) ++
          ["    target: #{Jason.encode!(subagent["target"] || subagent[:target])}"] ++
          maybe_yaml_line("peer_id", subagent["peer_id"] || subagent[:peer_id], "    ") ++
          maybe_yaml_line(
            "peer_id_context_key",
            subagent["peer_id_context_key"] || subagent[:peer_id_context_key],
            "    "
          )

      Enum.join(lines, "\n")
    end)
  end

  defp encode_yaml_context(context) when context == %{}, do: "  {}"

  defp encode_yaml_context(context) when is_map(context) do
    Enum.map_join(context, "\n", fn {key, value} ->
      "  #{yaml_key(key)}: #{Jason.encode!(value)}"
    end)
  end

  defp encode_yaml_plugins([]), do: "  []"
  defp encode_yaml_plugins(plugins), do: Enum.map_join(plugins, "\n", &"  - #{Jason.encode!(&1)}")

  defp encode_yaml_memory(nil), do: "  null"

  defp encode_yaml_memory(%{namespace: :per_agent} = memory) do
    [
      "  mode: #{Jason.encode!(Atom.to_string(memory.mode))}",
      "  namespace: \"per_agent\"",
      "  capture: #{Jason.encode!(Atom.to_string(memory.capture))}",
      "  retrieve:",
      "    limit: #{memory.retrieve.limit}",
      "  inject: #{Jason.encode!(Atom.to_string(memory.inject))}"
    ]
    |> Enum.join("\n")
  end

  defp encode_yaml_memory(%{namespace: {:shared, shared_namespace}} = memory) do
    [
      "  mode: #{Jason.encode!(Atom.to_string(memory.mode))}",
      "  namespace: \"shared\"",
      "  shared_namespace: #{Jason.encode!(shared_namespace)}",
      "  capture: #{Jason.encode!(Atom.to_string(memory.capture))}",
      "  retrieve:",
      "    limit: #{memory.retrieve.limit}",
      "  inject: #{Jason.encode!(Atom.to_string(memory.inject))}"
    ]
    |> Enum.join("\n")
  end

  defp encode_yaml_memory(%{namespace: {:context, key}} = memory) do
    [
      "  mode: #{Jason.encode!(Atom.to_string(memory.mode))}",
      "  namespace: \"context\"",
      "  context_namespace_key: #{Jason.encode!(key)}",
      "  capture: #{Jason.encode!(Atom.to_string(memory.capture))}",
      "  retrieve:",
      "    limit: #{memory.retrieve.limit}",
      "  inject: #{Jason.encode!(Atom.to_string(memory.inject))}"
    ]
    |> Enum.join("\n")
  end

  defp encode_yaml_hooks(hooks) do
    Enum.map_join([:before_turn, :after_turn, :on_interrupt], "\n", fn stage ->
      hook_names = Map.get(hooks, stage, [])

      [
        "  #{stage}:",
        if(hook_names == [],
          do: "    []",
          else: Enum.map_join(hook_names, "\n", &"    - #{Jason.encode!(&1)}")
        )
      ]
      |> Enum.join("\n")
    end)
  end

  defp encode_yaml_guardrails(guardrails) do
    Enum.map_join([:input, :output, :tool], "\n", fn stage ->
      guardrail_names = Map.get(guardrails, stage, [])

      case guardrail_names do
        [] ->
          "  #{stage}: []"

        names ->
          ["  #{stage}:" | Enum.map(names, &"    - #{Jason.encode!(&1)}")] |> Enum.join("\n")
      end
    end)
  end

  defp yaml_key(key) when is_atom(key), do: Atom.to_string(key)
  defp yaml_key(key) when is_binary(key), do: key

  defp maybe_yaml_line(key, value, indent \\ "    ")
  defp maybe_yaml_line(_key, nil, _indent), do: []
  defp maybe_yaml_line(_key, "", _indent), do: []

  defp maybe_yaml_line(key, value, indent) do
    ["#{indent}#{key}: #{Jason.encode!(value)}"]
  end
end
