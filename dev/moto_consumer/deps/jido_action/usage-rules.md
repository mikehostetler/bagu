# Jido Action Usage Rules

## Intent
Use actions as the smallest validated unit of behavior, then compose execution policy with `Jido.Exec` and workflow tools.

## Core Contracts
- Define actions with `use Jido.Action` and clear metadata (`name`, `description`, schema).
- Use **Zoi-first** schemas for new work; keep NimbleOptions for compatibility paths.
- Keep `run/2` contracts strict: `{:ok, result}` or `{:error, reason}`.
- Use `Jido.Exec` for retries, timeouts, async control, and telemetry in production paths.
- Keep action results deterministic where possible; isolate external IO.
- Keep `jido_action` focused on core and generic tools; use `jido_lib` for vendor/API-specific packs.

## Library Author Patterns
- Build thin domain actions: validate input -> call domain service -> normalize output.
- Wrap external APIs/filesystem/DB calls in dedicated actions instead of inline process logic.
- Compose multi-step workflows with `Jido.Instruction` and `Jido.Plan` rather than custom pipelines.
- Expose tool-facing actions with stable names and schemas via `Jido.Action.Tool`.

## QA Patterns
- Test validation failures, success path, and error path separately.
- For async execution, assert cleanup/timeout behavior via `Jido.Exec` APIs.
- Run `mix q` (`mix quality`) before release and keep docs/changelog in sync.

## Avoid
- Calling `run/2` directly in production orchestration when execution policy matters.
- New schema contracts without validation metadata.
- Hidden side effects that are not visible in params/context/result.

## References
- `README.md`
- `guides/`
- `AGENTS.md`
- https://hexdocs.pm/jido_action
- https://hexdocs.pm/usage_rules/readme.html#usage-rules
