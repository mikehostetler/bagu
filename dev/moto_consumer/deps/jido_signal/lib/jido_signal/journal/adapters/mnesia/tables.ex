defmodule Jido.Signal.Journal.Adapters.Mnesia.Tables do
  @moduledoc """
  Memento table definitions for the Mnesia journal adapter.
  """

  defmodule Signal do
    @moduledoc "Table for storing signals"
    use Memento.Table, attributes: [:id, :signal], type: :set
  end

  defmodule Cause do
    @moduledoc "Table for cause-effect relationships (cause -> effects)"
    use Memento.Table, attributes: [:cause_id, :effects], type: :set
  end

  defmodule Effect do
    @moduledoc "Table for effect-cause relationships (effect -> causes)"
    use Memento.Table, attributes: [:effect_id, :causes], type: :set
  end

  defmodule Conversation do
    @moduledoc "Table for conversation signal lists"
    use Memento.Table, attributes: [:conversation_id, :signals], type: :set
  end

  defmodule Checkpoint do
    @moduledoc "Table for subscription checkpoints"
    use Memento.Table, attributes: [:subscription_id, :checkpoint], type: :set
  end

  defmodule DLQ do
    @moduledoc "Table for dead letter queue entries"
    use Memento.Table,
      attributes: [:id, :subscription_id, :signal, :reason, :metadata, :inserted_at],
      type: :set,
      index: [:subscription_id]
  end
end
