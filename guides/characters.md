# Characters

Characters are structured persona inputs rendered into the effective system
prompt. They are backed by `jido_character`.

Use characters for identity, tone, and style. Use `instructions` for task,
policy, safety, and operational behavior.

## Compile-Time Character

```elixir
defmodule MyApp.SupportAgent do
  use Jidoka.Agent

  agent do
    id :support_agent
  end

  defaults do
    model :fast

    character %{
      name: "Support Advisor",
      identity: %{role: "Billing support specialist"},
      voice: %{tone: :professional, style: "Clear and direct"},
      instructions: ["Stay within published policy."]
    }

    instructions "Answer with the relevant policy first."
  end
end
```

Jidoka renders the character before `defaults.instructions`. That means the
character shapes voice and persona, while instructions still define the task.
See [Instructions](instructions.html) for how the rendered instruction string
composes with characters into the effective system prompt.

## Runtime Override

Use `character:` for one request when the caller needs a different voice:

```elixir
Jidoka.chat(pid, "Can I get a refund?",
  character: %{
    name: "Escalation Advisor",
    voice: %{tone: :warm},
    instructions: ["Be brief and empathetic."]
  }
)
```

Runtime `character:` overrides the compile-time character for that turn only.

## Character Sources

Jidoka accepts:

- inline maps parsed by `Jido.Character.new/1`
- modules generated with `use Jido.Character`

Inline maps are easiest for application-local definitions and imported specs.
Modules are better when a character should be reused across compiled agents.

## Imported Agents

Imported JSON/YAML agents have parity here: they support inline character maps
and can reference compiled characters by name through the
`available_characters:` registry. See [Imported Agents](imported-agents.html)
for the full spec.

```json
{
  "defaults": {
    "model": "fast",
    "character": {
      "name": "Support Advisor",
      "voice": {"tone": "professional"}
    },
    "instructions": "Answer with the relevant policy first."
  }
}
```

They can also reference string character names when the importing application
provides the `available_characters:` registry.

```elixir
Jidoka.import_agent(json,
  available_characters: %{
    "support_advisor" => MyApp.Characters.SupportAdvisor
  }
)
```

## Error Handling

Invalid character data returns a Jidoka validation error at runtime or a DSL error
at compile time:

```elixir
{:error, reason} = Jidoka.chat(pid, "Hello", character: %{voice: :bad_shape})
Jidoka.format_error(reason)
```

Keep character data small and explicit. Characters should not replace memory,
tools, workflows, or guardrails.
