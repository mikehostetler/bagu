defmodule TimeZoneInfo.Worker do
  @moduledoc false

  # Holds the state for `TimeZoneInfo` and starts the initial update and when
  # configured the automatic updates.

  use GenServer

  alias TimeZoneInfo.Updater
  alias TimeZoneInfo.UtcDateTime

  @timeout 3 * 60 * 1_000

  @doc """
  Starts a worker for `TimeZoneInfo`.
  """
  def start_link(opts) do
    opts = Keyword.put_new(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, nil, opts)
  end

  # API

  @doc """
  Runs the update process. This will also run at start up for the initialisation
  of `TimeZoneInfo`. This function returns the same as `state/0`.
  """
  def update(server \\ __MODULE__, opt) when opt in [:run, :force] do
    GenServer.call(server, {:update, opt}, @timeout)
  end

  @doc """
  Returns the state of the worker.

  Possible return values are:
  - `:ok`: `TimeZoneInfo` is initialised and the update process is disabled.
  - `{:next, milliseconds}`: `TimeZoneInfo` is initialised and the next update
    runs after `milliseconds`.
  - `{:error, reason}`
  """
  def state(server \\ __MODULE__), do: GenServer.call(server, :state)

  @doc """
  Returns the tuple `{:next, datetime}` where `datetime` is the date time for
  the next update. If `datetime` is `nil` no update process is started.
  """
  def next(server \\ __MODULE__), do: GenServer.call(server, :next)

  # Implementation

  @impl true
  def init(_opts) do
    state = do_update(:run)
    {:ok, state, :hibernate}
  end

  @impl true
  def handle_info(:update, state) do
    state = do_update(:run, state)
    {:noreply, state, :hibernate}
  end

  @impl true
  def handle_call({:update, opt}, _from, state) do
    state = do_update(opt, state)
    {:reply, reply(state), state, :hibernate}
  end

  def handle_call(:state, _from, state) do
    {:reply, reply(state), state, :hibernate}
  end

  def handle_call(:next, _from, state) do
    reply =
      case reply(state) do
        :ok ->
          {:next, :never}

        {:next, milliseconds} when is_integer(milliseconds) ->
          datetime = DateTime.add(UtcDateTime.now(), milliseconds, :millisecond)
          {:next, datetime}

        error ->
          error
      end

    {:reply, reply, state, :hibernate}
  end

  defp do_update(step, state \\ :init) do
    case Updater.update(step) do
      :ok ->
        :ok

      {:next, seconds} ->
        now = UtcDateTime.now(:unix)
        next = seconds - now
        timer = Process.send_after(self(), :update, next * 1_000)

        with {:next, last_timer} <- state, do: Process.cancel_timer(last_timer)

        {:next, timer}

      error ->
        error
    end
  end

  defp reply(state) do
    case state do
      :ok ->
        :ok

      {:next, timer} ->
        case Process.read_timer(timer) do
          false -> {:next, 0}
          milliseconds -> {:next, milliseconds}
        end

      error ->
        error
    end
  end
end
