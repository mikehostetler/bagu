defmodule Jidoka.Demo.Inventory do
  @moduledoc false

  @detail_levels [:debug, :trace]
  @row_width 13

  @spec print_compiled(String.t(), module(), Jidoka.Demo.Debug.log_level(), keyword()) :: :ok
  def print_compiled(title, agent_module, level, opts \\ []) when is_atom(agent_module) do
    print_definition(title, agent_module.__jidoka__(), level, opts)
  end

  @spec print_imported(String.t(), Jidoka.ImportedAgent.t(), Jidoka.Demo.Debug.log_level(), keyword()) ::
          :ok
  def print_imported(title, %Jidoka.ImportedAgent{} = agent, level, opts \\ []) do
    print_definition(title, Jidoka.ImportedAgent.definition(agent), level, opts)
  end

  @spec print_definition(String.t(), map(), Jidoka.Demo.Debug.log_level(), keyword()) :: :ok
  def print_definition(title, definition, level, opts \\ [])
      when is_map(definition) and level in [:info, :debug, :trace] do
    IO.puts(color(title, [:bright, :cyan]))

    opts
    |> Keyword.get(:notice, [])
    |> List.wrap()
    |> Enum.each(&IO.puts(color(&1, [:yellow])))

    IO.puts("Resolved model: #{inspect(Map.get(definition, :model))}")

    if level in @detail_levels do
      print_model(definition)
      print_import(opts)
      print_context(definition)
      print_capabilities(definition)
      print_pipeline(definition)
      print_subagents(definition)
      print_workflows(definition)
      print_handoffs(definition)
      print_try_next(Keyword.get(opts, :try, []))
    end

    IO.puts("")
    :ok
  end

  defp print_model(definition) do
    section("Model")
    row("configured", inspect(Map.get(definition, :configured_model)))
    row("resolved", inspect(Map.get(definition, :model)))
  end

  defp print_import(opts) do
    source = Keyword.get(opts, :source)
    registries = Keyword.get(opts, :registries, %{})

    if source || map_size(registries) > 0 do
      section("Import")
      if source, do: row("spec", source)

      Enum.each(registries, fn {label, values} ->
        maybe_row(to_string(label), format_list(values))
      end)
    end
  end

  defp print_context(definition) do
    section("Runtime Context")
    row("defaults", format_context(Map.get(definition, :context, %{})))

    case Map.get(definition, :context_schema) do
      nil -> row("schema", "(plain map)")
      schema -> row("schema", format_schema(schema))
    end
  end

  defp print_capabilities(definition) do
    section("Capabilities")
    row("tools", format_list(Map.get(definition, :tool_names, [])))
    maybe_row("ash", format_ash(definition))
    maybe_row("mcp", format_mcp(Map.get(definition, :mcp_tools, [])))
    maybe_row("skills", format_skills(Map.get(definition, :skills)))
    maybe_row("plugins", format_list(Map.get(definition, :plugin_names, [])))
    maybe_row("web", format_web(Map.get(definition, :web, [])))
    maybe_row("workflows", format_list(Map.get(definition, :workflow_names, [])))
    maybe_row("handoffs", format_list(Map.get(definition, :handoff_names, [])))
  end

  defp print_pipeline(definition) do
    rows =
      [
        {"memory", format_memory(Map.get(definition, :memory))},
        {"output", format_output(Map.get(definition, :output))},
        {"hooks", format_hooks(Map.get(definition, :hooks, %{}))},
        {"guardrails", format_guardrails(Map.get(definition, :guardrails, %{}))}
      ]
      |> Enum.reject(fn {_label, value} -> value in [nil, "", "(none)"] end)

    if rows != [] do
      section("Turn Pipeline")
      Enum.each(rows, fn {label, value} -> row(label, value) end)
    end
  end

  defp print_subagents(%{subagents: subagents}) when is_list(subagents) and subagents != [] do
    section("Subagents")

    Enum.each(subagents, fn subagent ->
      row(
        subagent.name,
        Enum.join(
          [
            format_target(subagent.target),
            "timeout=#{subagent.timeout}ms",
            "result=#{subagent.result}",
            "forwards=#{format_forward_context(subagent.forward_context)}"
          ],
          ", "
        )
      )
    end)
  end

  defp print_subagents(_definition), do: :ok

  defp print_workflows(%{workflows: workflows}) when is_list(workflows) and workflows != [] do
    section("Workflows")

    Enum.each(workflows, fn workflow ->
      row(
        workflow.name,
        Enum.join(
          [
            format_ref(workflow.workflow),
            "timeout=#{workflow.timeout}ms",
            "result=#{workflow.result}",
            "forwards=#{format_forward_context(workflow.forward_context)}"
          ],
          ", "
        )
      )
    end)
  end

  defp print_workflows(_definition), do: :ok

  defp print_handoffs(%{handoffs: handoffs}) when is_list(handoffs) and handoffs != [] do
    section("Handoffs")

    Enum.each(handoffs, fn handoff ->
      row(
        handoff.name,
        Enum.join(
          [
            format_ref(handoff.agent),
            format_target(handoff.target),
            "forwards=#{format_forward_context(handoff.forward_context)}"
          ],
          ", "
        )
      )
    end)
  end

  defp print_handoffs(_definition), do: :ok

  defp print_try_next([]), do: :ok

  defp print_try_next(prompts) do
    section("Try Next")

    Enum.each(prompts, fn prompt ->
      IO.puts("  #{color(prompt, [:green])}")
    end)
  end

  defp section(title) do
    IO.puts("")
    IO.puts(color(title, [:bright]))
  end

  defp row(label, value) do
    IO.puts("  #{color(String.pad_trailing(to_string(label), @row_width), [:faint])} #{value}")
  end

  defp maybe_row(_label, nil), do: :ok
  defp maybe_row(_label, ""), do: :ok
  defp maybe_row(_label, "(none)"), do: :ok
  defp maybe_row(label, value), do: row(label, value)

  defp format_context(context) when is_map(context) and map_size(context) == 0, do: "(empty)"

  defp format_context(context) when is_map(context) do
    context
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Enum.map_join(", ", fn {key, value} -> "#{key}=#{inspect(value)}" end)
  end

  defp format_context(other), do: inspect(other)

  defp format_web([]), do: "(none)"

  defp format_web(web) when is_list(web) do
    web
    |> Enum.map(fn capability ->
      "#{capability.mode}: #{format_list(Enum.map(capability.tools, &tool_name/1))}"
    end)
    |> Enum.join("; ")
  end

  defp tool_name(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :name, 0) do
      module.name()
    else
      inspect(module)
    end
  end

  defp format_schema(%Zoi.Types.Map{fields: fields}) when is_list(fields) do
    fields
    |> Enum.sort_by(fn {key, _schema} -> to_string(key) end)
    |> Enum.map_join(", ", fn {key, schema} -> "#{key}:#{format_schema_field(schema)}" end)
  end

  defp format_schema(_schema), do: "(custom schema)"

  defp format_schema_field(%Zoi.Types.Default{inner: inner, value: value}) do
    "#{schema_type(inner)} default=#{inspect(value)}"
  end

  defp format_schema_field(schema) do
    suffix =
      cond do
        schema.meta.required == true -> " required"
        schema.meta.required == false -> " optional"
        true -> ""
      end

    schema_type(schema) <> suffix
  end

  defp schema_type(%Zoi.Types.String{}), do: "string"
  defp schema_type(%Zoi.Types.Integer{}), do: "integer"
  defp schema_type(%Zoi.Types.Float{}), do: "float"
  defp schema_type(%Zoi.Types.Boolean{}), do: "boolean"
  defp schema_type(%Zoi.Types.Any{}), do: "any"
  defp schema_type(%Zoi.Types.Map{}), do: "map"
  defp schema_type(%Zoi.Types.Array{}), do: "list"
  defp schema_type(%Zoi.Types.Default{inner: inner}), do: schema_type(inner)

  defp schema_type(schema) when is_struct(schema) do
    schema.__struct__
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
  end

  defp format_ash(%{ash_resources: []}), do: nil

  defp format_ash(%{ash_resources: resources}) when is_list(resources) do
    case Jidoka.Agent.AshResources.expand(resources) do
      {:ok, %{tool_names: names}} -> format_list(names)
      _ -> format_list(Enum.map(resources, &short_module/1))
    end
  end

  defp format_ash(_definition), do: nil

  defp format_mcp([]), do: nil

  defp format_mcp(mcp_tools) do
    Enum.map_join(mcp_tools, ", ", fn entry ->
      endpoint = Map.get(entry, :endpoint) || Map.get(entry, "endpoint")
      prefix = Map.get(entry, :prefix) || Map.get(entry, "prefix")

      case prefix do
        nil -> inspect(endpoint)
        "" -> inspect(endpoint)
        value -> "#{inspect(endpoint)} as #{value}*"
      end
    end)
  end

  defp format_skills(nil), do: nil
  defp format_skills(%{refs: refs}), do: format_list(Enum.map(refs, &format_ref/1))
  defp format_skills(other), do: inspect(other)

  defp format_memory(nil), do: nil

  defp format_memory(memory) when is_map(memory) do
    [
      memory[:mode],
      format_memory_namespace(memory[:namespace]),
      "capture=#{memory[:capture]}",
      "inject=#{memory[:inject]}",
      "retrieve=#{get_in(memory, [:retrieve, :limit]) || "?"}"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end

  defp format_memory(other), do: inspect(other)

  defp format_memory_namespace({:context, key}), do: "namespace=context.#{key}"
  defp format_memory_namespace(:per_agent), do: "namespace=per_agent"
  defp format_memory_namespace(:shared), do: "namespace=shared"
  defp format_memory_namespace(nil), do: nil
  defp format_memory_namespace(other), do: "namespace=#{inspect(other)}"

  defp format_output(nil), do: nil

  defp format_output(%Jidoka.Output{} = output) do
    [
      "schema=#{format_output_schema(output.schema)}",
      "retries=#{output.retries}",
      "on_validation_error=#{output.on_validation_error}"
    ]
    |> Enum.join(", ")
  end

  defp format_output(other), do: inspect(other)

  defp format_output_schema(%Zoi.Types.Map{fields: fields}) when is_list(fields) do
    fields
    |> Enum.map(fn {key, _schema} -> to_string(key) end)
    |> Enum.sort()
    |> Enum.join("|")
  end

  defp format_output_schema(%{} = schema) do
    schema
    |> Map.get("properties", Map.get(schema, :properties, %{}))
    |> Map.keys()
    |> Enum.map(&to_string/1)
    |> Enum.sort()
    |> Enum.join("|")
  end

  defp format_output_schema(_schema), do: "custom"

  defp format_hooks(hooks) when is_map(hooks) do
    [
      stage_modules(:before, hooks[:before_turn]),
      stage_modules(:after, hooks[:after_turn]),
      stage_modules(:interrupt, hooks[:on_interrupt])
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end

  defp format_hooks(_hooks), do: nil

  defp format_guardrails(guardrails) when is_map(guardrails) do
    [
      stage_modules(:input, guardrails[:input]),
      stage_modules(:output, guardrails[:output]),
      stage_modules(:tool, guardrails[:tool])
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end

  defp format_guardrails(_guardrails), do: nil

  defp stage_modules(_stage, nil), do: nil
  defp stage_modules(_stage, []), do: nil

  defp stage_modules(stage, modules) do
    "#{stage}=#{Enum.map_join(modules, "|", &format_ref/1)}"
  end

  defp format_target(:ephemeral), do: "ephemeral"
  defp format_target(:auto), do: "auto"
  defp format_target({:peer, {:context, key}}), do: "peer=context.#{key}"
  defp format_target({:peer, peer_id}), do: "peer=#{peer_id}"
  defp format_target(other), do: inspect(other)

  defp format_forward_context(:public), do: "public"
  defp format_forward_context(:none), do: "none"
  defp format_forward_context({:only, keys}), do: "only #{format_key_list(keys)}"
  defp format_forward_context({:except, keys}), do: "except #{format_key_list(keys)}"
  defp format_forward_context(other), do: inspect(other)

  defp format_key_list(keys), do: keys |> Enum.map(&to_string/1) |> Enum.join("/")

  defp format_list([]), do: "(none)"
  defp format_list(items), do: Enum.map_join(items, ", ", &format_ref/1)

  defp format_ref(module) when is_atom(module), do: short_module(module)
  defp format_ref(other), do: to_string(other)

  defp short_module(module) when is_atom(module) do
    module
    |> Module.split()
    |> List.last()
  end

  defp color(text, styles) do
    if color?() do
      [styles, text]
      |> List.flatten()
      |> IO.ANSI.format(true)
      |> IO.iodata_to_binary()
    else
      text
    end
  end

  defp color? do
    System.get_env("NO_COLOR") in [nil, ""] and IO.ANSI.enabled?()
  end
end
