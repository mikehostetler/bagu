defmodule Jido.Signal.Names do
  @moduledoc """
  Resolves process names based on optional `jido:` instance scoping.

  When `jido:` option is present, routes all operations through instance-scoped
  supervisors. When absent, uses global defaults for zero-config operation.

  ## Instance Isolation

  The `jido:` option enables complete isolation between instances:
  - Each instance has its own Registry, TaskSupervisor, and Bus processes
  - No cross-instance signal leakage
  - Easy to test isolation guarantees

  ## Examples

      # Global (default) - uses Jido.Signal.Registry
      Names.registry([])
      #=> Jido.Signal.Registry

      # Instance-scoped - uses MyApp.Jido.Signal.Registry
      Names.registry(jido: MyApp.Jido)
      #=> MyApp.Jido.Signal.Registry

  """

  @type opts :: keyword()

  @doc """
  Returns the Registry name for the given instance scope.

  ## Examples

      iex> Jido.Signal.Names.registry([])
      Jido.Signal.Registry

      iex> Jido.Signal.Names.registry(jido: MyApp.Jido)
      MyApp.Jido.Signal.Registry

  """
  @spec registry(opts()) :: atom()
  def registry(opts) do
    scoped(opts, Jido.Signal.Registry)
  end

  @doc """
  Returns the TaskSupervisor name for the given instance scope.

  ## Examples

      iex> Jido.Signal.Names.task_supervisor([])
      Jido.Signal.TaskSupervisor

      iex> Jido.Signal.Names.task_supervisor(jido: MyApp.Jido)
      MyApp.Jido.Signal.TaskSupervisor

  """
  @spec task_supervisor(opts()) :: atom()
  def task_supervisor(opts) do
    scoped(opts, Jido.Signal.TaskSupervisor)
  end

  @doc """
  Returns the Supervisor name for the given instance scope.

  ## Examples

      iex> Jido.Signal.Names.supervisor([])
      Jido.Signal.Supervisor

      iex> Jido.Signal.Names.supervisor(jido: MyApp.Jido)
      MyApp.Jido.Signal.Supervisor

  """
  @spec supervisor(opts()) :: atom()
  def supervisor(opts) do
    scoped(opts, Jido.Signal.Supervisor)
  end

  @doc """
  Returns the Extension Registry name for the given instance scope.

  ## Examples

      iex> Jido.Signal.Names.ext_registry([])
      Jido.Signal.Ext.Registry

      iex> Jido.Signal.Names.ext_registry(jido: MyApp.Jido)
      MyApp.Jido.Signal.Ext.Registry

  """
  @spec ext_registry(opts()) :: atom()
  def ext_registry(opts) do
    scoped(opts, Jido.Signal.Ext.Registry)
  end

  @doc """
  Resolves a module name based on instance scope.

  When `jido:` option is nil or not present, returns the default module.
  When `jido:` option is present, concatenates the instance with
  the default module's relative path under `Jido.Signal`.

  ## Examples

      iex> Jido.Signal.Names.scoped([], Jido.Signal.Registry)
      Jido.Signal.Registry

      iex> Jido.Signal.Names.scoped([jido: MyApp.Jido], Jido.Signal.Registry)
      MyApp.Jido.Signal.Registry

  """
  @spec scoped(opts(), module()) :: atom()
  def scoped(opts, default) when is_list(opts) and is_atom(default) do
    case Keyword.get(opts, :jido) do
      nil ->
        default

      instance when is_atom(instance) ->
        # Get the relative path after Jido (e.g., Signal.Registry from Jido.Signal.Registry)
        default_parts = Module.split(default)

        relative_parts =
          case default_parts do
            ["Jido" | rest] -> rest
            parts -> parts
          end

        Module.concat([instance | relative_parts])
    end
  end

  @doc """
  Extracts the jido instance from options, returning nil if not present.
  """
  @spec instance(opts()) :: atom() | nil
  def instance(opts) when is_list(opts) do
    Keyword.get(opts, :jido)
  end
end
