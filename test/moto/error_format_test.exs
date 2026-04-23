defmodule MotoTest.ErrorFormatTest do
  use ExUnit.Case, async: true

  test "formats invalid context type errors" do
    error = Moto.Error.invalid_context(:expected_map, value: [1, 2])

    assert %Moto.Error.ValidationError{field: :context, value: [1, 2]} = error

    assert Moto.format_error(error) ==
             "Invalid context: pass `context:` as a map or keyword list."
  end

  test "formats schema errors in stable sorted order" do
    error =
      Moto.Error.invalid_context(
        {:schema,
         %{
           tenant: ["invalid type: expected string"],
           account_id: ["is required"]
         }},
        value: %{tenant: 123}
      )

    assert %Moto.Error.ValidationError{details: %{reason: :schema}} = error

    assert Moto.format_error(error) ==
             "Invalid context:\n- account_id: is required\n- tenant: invalid type: expected string"
  end

  test "formats invalid public tool_context option" do
    error = Moto.Error.invalid_option(:tool_context, :use_context, value: %{tenant: "acme"})

    assert %Moto.Error.ValidationError{field: :tool_context} = error

    assert Moto.format_error(error) ==
             "Invalid option: use `context:` for request-scoped data; `tool_context:` is internal."
  end

  test "formats missing context and domain mismatch errors" do
    assert Moto.format_error(Moto.Error.missing_context(:actor)) ==
             "Missing required context key `actor`. Pass it with `context: %{actor: ...}`."

    assert Moto.format_error(Moto.Error.invalid_context({:domain_mismatch, MyApp.Domain, Other.Domain})) ==
             "Invalid context: expected `domain` to be MyApp.Domain, got Other.Domain."
  end

  test "falls back to inspect for unknown errors" do
    assert Moto.format_error({:unhandled, :shape}) == "{:unhandled, :shape}"
  end

  test "formats Splode error classes in stable order" do
    error =
      Moto.Error.to_class([
        Moto.Error.execution_error("Workflow step failed."),
        Moto.Error.validation_error("Input is invalid.")
      ])

    assert Moto.format_error(error) ==
             "Multiple Moto errors:\n- Input is invalid.\n- Workflow step failed."
  end
end
