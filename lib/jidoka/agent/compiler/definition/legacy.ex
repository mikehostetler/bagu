defmodule Jidoka.Agent.Definition.Legacy do
  @moduledoc false

  @legacy_sections [
    memory: "Move `memory do ... end` inside `lifecycle do ... end`.",
    tools: "Move `tool`, `ash_resource`, and `mcp_tools` declarations inside `capabilities do ... end`.",
    skills: "Move `skill` and `load_path` declarations inside `capabilities do ... end`.",
    plugins: "Move `plugin` declarations inside `capabilities do ... end`.",
    subagents: "Move `subagent` declarations inside `capabilities do ... end`.",
    handoffs: "Move `handoff` declarations inside `capabilities do ... end`.",
    hooks: "Move hook declarations inside `lifecycle do ... end`.",
    guardrails:
      "Move guardrails inside `lifecycle do ... end` and rename `input`, `output`, and `tool` to `input_guardrail`, `output_guardrail`, and `tool_guardrail`."
  ]

  @spec reject_legacy_placements!(module()) :: :ok
  def reject_legacy_placements!(owner_module) do
    reject_legacy_agent_option!(
      owner_module,
      :model,
      "Move `model` into `defaults do ... end`."
    )

    reject_legacy_agent_option!(
      owner_module,
      :system_prompt,
      "Rename `system_prompt` to `instructions` inside `defaults do ... end`."
    )

    Enum.each(@legacy_sections, fn {section, hint} ->
      if legacy_section_present?(owner_module, section) do
        raise Jidoka.Agent.Dsl.Error.exception(
                message: "Top-level `#{section} do ... end` is not valid in the beta Jidoka DSL.",
                path: [section],
                hint: hint,
                module: owner_module,
                location: Spark.Dsl.Extension.get_section_anno(owner_module, [section])
              )
      end
    end)
  end

  defp reject_legacy_agent_option!(owner_module, option, hint) do
    value = Spark.Dsl.Extension.get_opt(owner_module, [:agent], option)

    unless is_nil(value) do
      raise Jidoka.Agent.Dsl.Error.exception(
              message: "`agent.#{option}` is not valid in the beta Jidoka DSL.",
              path: [:agent, option],
              value: value,
              hint: hint,
              module: owner_module
            )
    end
  end

  defp legacy_section_present?(owner_module, section) do
    Spark.Dsl.Extension.get_entities(owner_module, [section]) != [] or
      not is_nil(Spark.Dsl.Extension.get_section_anno(owner_module, [section]))
  rescue
    _ -> false
  end
end
