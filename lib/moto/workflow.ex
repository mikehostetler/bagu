defmodule Moto.Workflow do
  @moduledoc """
  Spark-backed workflow DSL and runtime facade for Moto.

  `Moto.Workflow` compiles a small public workflow DSL into an internal
  `jido_runic` graph. Public code describes inputs, steps, and output wiring;
  Moto keeps Runic facts, directives, and strategy internals behind the runtime.
  """

  @doc """
  Runs a compiled Moto workflow module.
  """
  @spec run(module(), map() | keyword(), keyword()) :: {:ok, term()} | {:error, term()}
  def run(workflow_module, input, opts \\ []) when is_atom(workflow_module) and is_list(opts) do
    with {:ok, definition} <- definition(workflow_module) do
      Moto.Workflow.Runtime.run(definition, input, opts)
    end
  end

  @doc """
  Returns Moto's inspection view of a compiled workflow definition.
  """
  @spec inspect_workflow(module()) :: {:ok, map()} | {:error, term()}
  def inspect_workflow(workflow_module) when is_atom(workflow_module) do
    with {:ok, definition} <- definition(workflow_module) do
      {:ok, Moto.Workflow.Runtime.inspect_definition(definition)}
    end
  end

  @doc false
  @spec definition(module()) :: {:ok, map()} | {:error, term()}
  def definition(workflow_module) when is_atom(workflow_module) do
    _ = Code.ensure_loaded(workflow_module)

    cond do
      function_exported?(workflow_module, :__moto__, 0) ->
        case workflow_module.__moto__() do
          %{kind: :workflow_definition} = definition -> {:ok, definition}
          _other -> {:error, Moto.Error.config_error("Module is not a Moto workflow.", module: workflow_module)}
        end

      true ->
        {:error, Moto.Error.config_error("Module is not a Moto workflow.", module: workflow_module)}
    end
  end

  defmacro __using__(opts \\ []) do
    if opts != [] do
      raise CompileError,
        file: __CALLER__.file,
        line: __CALLER__.line,
        description:
          "Moto.Workflow uses a Spark DSL. Use `use Moto.Workflow` and configure it inside `workflow do ... end`."
    end

    quote location: :keep do
      use Moto.Workflow.SparkDsl

      @before_compile Moto.Workflow
    end
  end

  defmacro __before_compile__(env) do
    Moto.Workflow.Build.before_compile(env)
  end
end
