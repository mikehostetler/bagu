defmodule Jidoka.Adapter.Runic.Identity do
  @moduledoc false
end

if Code.ensure_loaded?(Runic.Identity.Projectable) do
  defimpl Runic.Identity.Projectable, for: Jidoka.Turn.State do
    def identity_document(state), do: Jidoka.Projection.Turn.project(state)
  end

  defimpl Runic.Identity.Projectable, for: Jidoka.Workflow.Spec do
    def identity_document(spec), do: Jidoka.Projection.Workflow.project(spec)
  end

  defimpl Runic.Identity.Projectable, for: Jidoka.Workflow.Step do
    def identity_document(step), do: Jidoka.Projection.Workflow.project(step)
  end

  defimpl Runic.Identity.Projectable, for: Jidoka.Context do
    def identity_document(context) do
      context
      |> Jidoka.Context.data()
      |> Jidoka.Portable.project()
    end
  end

  defimpl Runic.Identity.Projectable, for: Jido.Action.Catalog.Entry do
    def identity_document(entry), do: entry |> Map.from_struct() |> Jidoka.Portable.project()
  end
end
