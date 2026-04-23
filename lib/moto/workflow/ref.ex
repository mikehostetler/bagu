defmodule Moto.Workflow.Ref do
  @moduledoc """
  Reference helpers for `Moto.Workflow` DSL data wiring.
  """

  @type t ::
          {:moto_workflow_ref, :input, atom() | String.t()}
          | {:moto_workflow_ref, :from, atom(), nil | [atom() | String.t()]}
          | {:moto_workflow_ref, :context, atom() | String.t()}
          | {:moto_workflow_ref, :value, term()}

  @doc """
  References a top-level workflow input field.
  """
  @spec input(atom() | String.t()) :: t()
  def input(key) when is_atom(key) or is_binary(key), do: {:moto_workflow_ref, :input, key}

  @doc """
  References a prior step output.
  """
  @spec from(atom()) :: t()
  def from(step) when is_atom(step), do: {:moto_workflow_ref, :from, step, nil}

  @doc """
  References a field on a prior step output.
  """
  @spec from(atom(), atom() | String.t() | [atom() | String.t()]) :: t()
  def from(step, field) when is_atom(step) and (is_atom(field) or is_binary(field)),
    do: {:moto_workflow_ref, :from, step, [field]}

  def from(step, path) when is_atom(step) and is_list(path),
    do: {:moto_workflow_ref, :from, step, path}

  @doc """
  References runtime side-band workflow context.
  """
  @spec context(atom() | String.t()) :: t()
  def context(key) when is_atom(key) or is_binary(key), do: {:moto_workflow_ref, :context, key}

  @doc """
  Marks a static value explicitly.
  """
  @spec value(term()) :: t()
  def value(term), do: {:moto_workflow_ref, :value, term}

  @doc false
  @spec ref?(term()) :: boolean()
  def ref?({:moto_workflow_ref, kind, _key}) when kind in [:input, :context, :value], do: true
  def ref?({:moto_workflow_ref, :from, step, path}) when is_atom(step) and (is_nil(path) or is_list(path)), do: true
  def ref?(_other), do: false
end
