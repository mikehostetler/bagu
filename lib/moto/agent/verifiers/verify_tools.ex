defmodule Moto.Agent.Verifiers.VerifyTools do
  @moduledoc false

  use Spark.Dsl.Verifier

  @impl true
  def verify(dsl_state) do
    dsl_state
    |> Spark.Dsl.Verifier.get_entities([:tools])
    |> Enum.filter(&match?(%Moto.Agent.Dsl.Tool{}, &1))
    |> Enum.reduce_while({:ok, MapSet.new()}, fn tool_ref, {:ok, seen_names} ->
      module = tool_ref.module

      case Moto.Tool.tool_name(module) do
        {:ok, name} ->
          if MapSet.member?(seen_names, name) do
            {:halt, {:error, duplicate_tool_error(dsl_state, tool_ref, name)}}
          else
            {:cont, {:ok, MapSet.put(seen_names, name)}}
          end

        {:error, message} ->
          {:halt, {:error, tool_error(dsl_state, tool_ref, message)}}
      end
    end)
    |> case do
      {:ok, _} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  defp duplicate_tool_error(dsl_state, tool_ref, name) do
    Spark.Error.DslError.exception(
      message: "tool #{inspect(name)} is defined more than once",
      path: [:tools, :tool],
      module: Spark.Dsl.Verifier.get_persisted(dsl_state, :module),
      location: Spark.Dsl.Entity.anno(tool_ref)
    )
  end

  defp tool_error(dsl_state, tool_ref, message) do
    Spark.Error.DslError.exception(
      message: message,
      path: [:tools, :tool],
      module: Spark.Dsl.Verifier.get_persisted(dsl_state, :module),
      location: Spark.Dsl.Entity.anno(tool_ref)
    )
  end
end
