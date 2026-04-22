%Doctor.Config{
  ignore_modules: [
    # Spark/Ash/Jido generate helper modules that either point at `nofile` or
    # expand quoted DSL code in ways Doctor cannot attribute cleanly.
    ~r/^Inspect\.Moto\.Demo\./,
    ~r/^Moto\.Agent\.Dsl/,
    ~r/^Moto\.Agent\.Verifiers\./,
    Moto.Context,
    Moto.Debug,
    ~r/^Moto\.Demo\./,
    Moto.Guardrails,
    ~r/^Moto\.Guardrails\./,
    Moto.Hooks,
    ~r/^Moto\.Hooks\./,
    Moto.ImportedAgent,
    ~r/^Moto\.ImportedAgent\./,
    Moto.Inspection,
    Moto.MCP,
    Moto.Memory,
    ~r/^Moto\.Plugins\./,
    Moto.Skill,
    Moto.StageRefs
  ],
  ignore_paths: [
    "nofile",
    ~r"^lib/mix/tasks/",
    ~r"^lib/moto/agent/",
    ~r"^lib/moto/demo/",
    ~r"^lib/moto/plugins/",
    ~r"^lib/moto/imported_agent/(codec|registries)\.ex$",
    ~r"^lib/moto/mcp/sync_tools_to_agent\.ex$",
    ~r"^lib/moto/subagent/"
  ],
  min_module_doc_coverage: 60,
  min_module_spec_coverage: 0,
  min_overall_doc_coverage: 90,
  min_overall_moduledoc_coverage: 100,
  min_overall_spec_coverage: 0,
  exception_moduledoc_required: true,
  raise: false,
  reporter: Doctor.Reporters.Full,
  struct_type_spec_required: false,
  umbrella: false
}
