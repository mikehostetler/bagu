defmodule Jido.Signal.Journal.Persistence do
  @moduledoc """
  Defines the behavior for Journal persistence adapters.
  """
  alias Jido.Signal

  @type signal_id :: String.t()
  @type conversation_id :: String.t()
  @type subscription_id :: String.t()
  @type checkpoint :: non_neg_integer()
  @type error :: {:error, term()}

  @callback init() :: :ok | {:ok, pid()} | error()

  @callback put_signal(Signal.t(), pid() | nil) :: :ok | error()

  @callback get_signal(signal_id(), pid() | nil) ::
              {:ok, Signal.t()} | {:error, :not_found} | error()

  @callback put_cause(signal_id(), signal_id(), pid() | nil) :: :ok | error()

  @callback get_effects(signal_id(), pid() | nil) :: {:ok, MapSet.t()} | error()

  @callback get_cause(signal_id(), pid() | nil) ::
              {:ok, signal_id()} | {:error, :not_found} | error()

  @callback put_conversation(conversation_id(), signal_id(), pid() | nil) :: :ok | error()

  @callback get_conversation(conversation_id(), pid() | nil) :: {:ok, MapSet.t()} | error()

  @callback put_checkpoint(subscription_id(), checkpoint(), pid() | nil) :: :ok | error()

  @callback get_checkpoint(subscription_id(), pid() | nil) ::
              {:ok, checkpoint()} | {:error, :not_found} | error()

  @callback delete_checkpoint(subscription_id(), pid() | nil) :: :ok | error()

  @type dlq_entry :: %{
          id: String.t(),
          subscription_id: String.t(),
          signal: Signal.t(),
          reason: term(),
          metadata: map(),
          inserted_at: DateTime.t()
        }

  @callback put_dlq_entry(subscription_id(), Signal.t(), term(), map(), pid() | nil) ::
              {:ok, String.t()} | error()

  @callback get_dlq_entries(subscription_id(), pid() | nil) ::
              {:ok, [dlq_entry()]} | error()

  @callback delete_dlq_entry(String.t(), pid() | nil) :: :ok | error()

  @callback clear_dlq(subscription_id(), pid() | nil) :: :ok | error()
end
