defmodule Jidoka.Examples.DataAnalyst.Tools.QueryRevenue do
  @moduledoc false

  use Jidoka.Tool,
    description: "Queries fixture-backed monthly revenue for a product line.",
    schema:
      Zoi.object(%{
        product: Zoi.string(),
        period: Zoi.string()
      })

  @revenue %{
    {:core, "2026-01"} => 128_000.0,
    {:core, "2026-02"} => 134_500.0,
    {:core, "2026-03"} => 151_250.0,
    {:platform, "2026-01"} => 86_000.0,
    {:platform, "2026-02"} => 91_000.0,
    {:platform, "2026-03"} => 97_500.0
  }

  @impl true
  def run(%{product: product, period: period}, _context) do
    product = normalize_product(product)
    period = normalize_period(period)

    case Map.fetch(@revenue, {product, period}) do
      {:ok, revenue} -> {:ok, %{product: product, period: period, revenue: revenue}}
      :error -> {:error, {:missing_revenue, product, period}}
    end
  end

  defp normalize_product(product) when is_atom(product), do: product

  defp normalize_product(product) when is_binary(product) do
    case String.downcase(product) do
      "core" -> :core
      "platform" -> :platform
      other -> other
    end
  end

  defp normalize_period(period) when is_binary(period) do
    case String.downcase(String.trim(period)) do
      "january 2026" -> "2026-01"
      "jan 2026" -> "2026-01"
      "february 2026" -> "2026-02"
      "feb 2026" -> "2026-02"
      "march 2026" -> "2026-03"
      "mar 2026" -> "2026-03"
      other -> other
    end
  end

  defp normalize_period(period), do: period
end
