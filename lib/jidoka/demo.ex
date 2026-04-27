defmodule Jidoka.Demo do
  @moduledoc false

  alias Jidoka.Demo.Loader

  @demos %{
    "chat" => %{loader: :chat, module: Jidoka.Examples.Chat.Demo},
    "imported" => %{loader: :chat, module: Jidoka.Examples.Chat.ImportedDemo},
    "trace" => %{loader: :trace, module: Jidoka.Examples.Trace.Demo},
    "workflow" => %{loader: :workflow, module: Jidoka.Examples.Workflow.Demo},
    "orchestrator" => %{loader: :orchestrator, module: Jidoka.Examples.Orchestrator.Demo},
    "kitchen_sink" => %{loader: :kitchen_sink, module: Jidoka.Examples.KitchenSink.Demo}
  }

  @doc false
  @spec names() :: [String.t()]
  def names do
    @demos
    |> Map.keys()
    |> Enum.sort()
  end

  @doc false
  @spec run(String.t(), [String.t()]) :: :ok | {:error, String.t()}
  def run(name, argv) when is_binary(name) and is_list(argv) do
    with {:ok, module} <- load(name) do
      apply(module, :main, [argv])
    end
  end

  @doc false
  @spec load(String.t()) :: {:ok, module()} | {:error, String.t()}
  def load(name) when is_binary(name) do
    case Map.fetch(@demos, name) do
      {:ok, demo} ->
        Loader.load!(demo.loader)
        {:ok, demo.module}

      :error ->
        unknown_demo(name)
    end
  end

  @doc false
  @spec preload(String.t()) :: :ok | {:error, String.t()}
  def preload(name) when is_binary(name) do
    case Map.fetch(@demos, name) do
      {:ok, demo} ->
        demo
        |> Map.get(:preload, [])
        |> Enum.each(&Loader.load!/1)

        :ok

      :error ->
        unknown_demo(name)
    end
  end

  defp unknown_demo(name) do
    {:error, "unknown demo #{inspect(name)}. Expected #{Enum.map_join(names(), ", ", &"`#{&1}`")}."}
  end
end
