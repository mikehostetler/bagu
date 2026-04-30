# Release Checklist

Current beta candidate: `1.0.0-beta.1`

## Local Verification

Run these from the package root:

```bash
mix deps.get
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix docs --warnings-as-errors
mix hex.build --unpack
mix hex.publish --dry-run
```

## Hex Dependency Readiness

Hex package metadata does not include git dependencies. Before publishing
Jidoka to Hex, every runtime dependency required to compile Jidoka from a Hex
consumer must either be published on Hex or moved behind an optional integration
boundary.

Runtime dependencies that still need a Hex-ready decision:

- `jido_ai`: publish a release containing structured output support, then switch
  Jidoka from the `feat/structured-output` branch to a Hex constraint.
- `ash_jido`: publish to Hex or make Ash resource support optional.
- `jido_character`: publish to Hex or make character support optional.
- `jido_mcp`: publish to Hex or make MCP support optional.
- `jido_memory`: publish to Hex or make memory support optional.
- `jido_runic`: publish to Hex or make workflow support optional.

`jido` and `jido_browser` are already available on Hex.

## Publish

After the dependency posture is Hex-ready and the dry run passes:

```bash
git tag v1.0.0-beta.1
git push origin v1.0.0-beta.1
mix hex.publish
```

