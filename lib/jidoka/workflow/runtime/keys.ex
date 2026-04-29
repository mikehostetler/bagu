defmodule Jidoka.Workflow.Runtime.Keys do
  @moduledoc false

  @definition_key :__jidoka_workflow_definition__
  @step_key :__jidoka_workflow_step__
  @state_key :__jidoka_workflow_state__
  @runner_key :__jidoka_workflow_runner__

  @spec definition_key() :: atom()
  def definition_key, do: @definition_key

  @spec step_key() :: atom()
  def step_key, do: @step_key

  @spec state_key() :: atom()
  def state_key, do: @state_key

  @spec runner_key() :: atom()
  def runner_key, do: @runner_key
end
