# Used by "mix format"
[
  locals_without_parens: [
    after_turn: 1,
    ash_resource: 1,
    before_turn: 1,
    capture: 1,
    id: 1,
    inject: 1,
    input_guardrail: 1,
    instructions: 1,
    load_path: 1,
    mcp_tools: 1,
    mode: 1,
    model: 1,
    namespace: 1,
    on_interrupt: 1,
    output_guardrail: 1,
    plugin: 1,
    retrieve: 1,
    schema: 1,
    shared_namespace: 1,
    skill: 1,
    subagent: 1,
    subagent: 2,
    tool: 1,
    tool_guardrail: 1
  ],
  inputs: [
    "{mix,.formatter,.credo,.doctor}.exs",
    "{config,examples,lib,test}/**/*.{ex,exs}"
  ],
  line_length: 120
]
