# Moto Consumer

Small local integration harness for `moto` + `ash_jido`.

This consumer app exists to validate real Ash resource integration behavior
without coupling those checks to Moto's unit tests.

It currently verifies:

- AshJido actor passthrough from `scope` when `actor` is omitted
- authorization failure when neither `actor` nor `scope.actor` is present
- Moto's current `ash_resource` behavior: no default actor is supplied, and
  `Moto.Agent` requires an explicit `context.actor`

## Run

```bash
cd dev/moto_consumer
mix setup
mix test
```
