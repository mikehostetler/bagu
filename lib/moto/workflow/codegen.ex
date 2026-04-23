defmodule Moto.Workflow.Codegen do
  @moduledoc false

  @spec emit(Moto.Workflow.Definition.t()) :: Macro.t()
  def emit(definition) when is_map(definition) do
    public_definition = definition.public_definition

    quote location: :keep do
      @doc """
      Returns Moto's compiled workflow-definition metadata for inspection tooling.
      """
      @spec __moto__() :: map()
      def __moto__, do: unquote(Macro.escape(public_definition))

      @doc """
      Returns the stable public workflow id.
      """
      @spec id() :: String.t()
      def id, do: unquote(definition.id)

      @doc """
      Returns the configured Zoi workflow input schema.
      """
      @spec input_schema() :: Zoi.schema()
      def input_schema, do: unquote(Macro.escape(definition.input_schema))

      @doc """
      Returns the compiled workflow steps.
      """
      @spec steps() :: [map()]
      def steps, do: unquote(Macro.escape(definition.steps))

      @doc """
      Returns the workflow output selector.
      """
      @spec output() :: term()
      def output, do: unquote(Macro.escape(definition.output))

      @doc """
      Builds the internal `Runic.Workflow` graph for this Moto workflow.
      """
      @spec build_workflow() :: Runic.Workflow.t()
      def build_workflow, do: Moto.Workflow.Runtime.build_workflow(__moto__())

      @doc """
      Runs this workflow through Moto's workflow runtime.
      """
      @spec run(map() | keyword(), keyword()) :: {:ok, term()} | {:error, term()}
      def run(input, opts \\ []), do: Moto.Workflow.run(__MODULE__, input, opts)
    end
  end
end
