defmodule Jidoka.Agent.Definition.OutputConfig do
  @moduledoc false

  @spec resolve!(module()) :: Jidoka.Output.t() | nil
  def resolve!(owner_module) do
    schema = Spark.Dsl.Extension.get_opt(owner_module, [:agent, :output], :schema)

    if is_nil(schema) do
      nil
    else
      retries = Spark.Dsl.Extension.get_opt(owner_module, [:agent, :output], :retries, 1)
      mode = Spark.Dsl.Extension.get_opt(owner_module, [:agent, :output], :on_validation_error, :repair)

      case Jidoka.Output.new(schema: schema, retries: retries, on_validation_error: mode) do
        {:ok, %Jidoka.Output{schema_kind: :zoi} = output} ->
          output

        {:ok, %Jidoka.Output{schema_kind: :json_schema}} ->
          raise_output_error!(
            owner_module,
            "agent.output.schema must be a Zoi object/map schema in the Elixir DSL.",
            schema,
            "Use `schema Zoi.object(%{...})`. JSON Schema maps are only accepted in imported specs."
          )

        {:error, message} ->
          raise_output_error!(
            owner_module,
            message,
            schema,
            "Use `output do schema Zoi.object(%{...}) end` with non-negative retries and :repair or :error mode."
          )
      end
    end
  end

  defp raise_output_error!(owner_module, message, value, hint) do
    raise Jidoka.Agent.Dsl.Error.exception(
            message: message,
            path: [:agent, :output],
            value: value,
            hint: hint,
            module: owner_module,
            location: Spark.Dsl.Extension.get_section_anno(owner_module, [:agent, :output])
          )
  end
end
