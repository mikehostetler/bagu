defmodule JidokaConsumer.Support.Data do
  @moduledoc false

  @spec customer_profile(String.t()) :: map()
  def customer_profile(account_id) do
    base =
      case account_id do
        "acct_vip" ->
          %{tier: "vip", plan: "priority", tenure_months: 48, region: "us", order_count: 27}

        "acct_trial" ->
          %{tier: "trial", plan: "starter", tenure_months: 1, region: "us", order_count: 1}

        "acct_eu" ->
          %{tier: "standard", plan: "growth", tenure_months: 18, region: "eu", order_count: 8}

        _other ->
          %{tier: "standard", plan: "growth", tenure_months: 9, region: "us", order_count: 6}
      end

    Map.merge(base, %{
      account_id: account_id,
      status: "active",
      health: "good"
    })
  end

  @spec order_snapshot(String.t(), String.t()) :: map()
  def order_snapshot(account_id, order_id) do
    base =
      case order_id do
        "ord_damaged" ->
          %{
            status: "delivered",
            age_days: 4,
            total_cents: 12_900,
            issue: "damaged_item",
            shipped_via: "ups"
          }

        "ord_late" ->
          %{
            status: "in_transit",
            age_days: 9,
            total_cents: 5_900,
            issue: "carrier_delay",
            shipped_via: "fedex"
          }

        "ord_old" ->
          %{
            status: "delivered",
            age_days: 45,
            total_cents: 8_400,
            issue: "buyer's_remorse",
            shipped_via: "ups"
          }

        _other ->
          %{
            status: "delivered",
            age_days: 12,
            total_cents: 7_500,
            issue: "general_return",
            shipped_via: "usps"
          }
      end

    Map.merge(base, %{
      account_id: account_id,
      order_id: order_id,
      currency: "USD"
    })
  end

  @spec refund_policy(map(), map(), String.t()) :: map()
  def refund_policy(customer, order, reason) do
    reason = String.downcase(reason)

    cond do
      String.contains?(reason, "damag") or order.issue == "damaged_item" ->
        %{
          decision: :approve,
          refund_type: :original_payment,
          rationale: "Delivered damaged goods are auto-approved for refund.",
          next_action: "Issue refund and apologize."
        }

      order.status != "delivered" ->
        %{
          decision: :manual_review,
          refund_type: :hold,
          rationale: "Shipment has not completed delivery; confirm final carrier state first.",
          next_action: "Escalate to order operations."
        }

      order.age_days > 30 ->
        %{
          decision: :deny,
          refund_type: :none,
          rationale: "Return window is closed after 30 days.",
          next_action: "Offer store credit only if a human approves."
        }

      customer.tier == "vip" and order.age_days <= 21 ->
        %{
          decision: :approve,
          refund_type: :original_payment,
          rationale: "Priority customers receive an extended 21-day discretionary refund window.",
          next_action: "Issue refund."
        }

      String.contains?(reason, "duplicate") ->
        %{
          decision: :approve,
          refund_type: :original_payment,
          rationale: "Duplicate charges are auto-approved once the order record matches.",
          next_action: "Issue refund."
        }

      true ->
        %{
          decision: :manual_review,
          refund_type: :hold,
          rationale: "Case needs an agent decision under the standard return policy.",
          next_action: "Queue for billing review."
        }
    end
  end

  @spec escalation_classification(map(), String.t()) :: map()
  def escalation_classification(customer, issue) do
    issue = String.downcase(issue)

    severity =
      cond do
        contains_any?(issue, ["legal", "chargeback", "breach", "security"]) -> :critical
        contains_any?(issue, ["cancel", "locked out", "cannot log in", "outage"]) -> :high
        customer.tier == "vip" and contains_any?(issue, ["slow", "broken", "blocked"]) -> :high
        contains_any?(issue, ["confused", "question", "how do i"]) -> :low
        true -> :medium
      end

    queue =
      case severity do
        :critical -> "exec_support"
        :high -> "tier2_support"
        :medium -> "tier1_support"
        :low -> "self_serve"
      end

    %{
      severity: severity,
      queue: queue,
      requires_human: severity in [:critical, :high],
      sla_minutes: sla_minutes(severity),
      summary: "#{String.upcase(to_string(severity))} support case for #{customer.account_id}"
    }
  end

  defp contains_any?(value, needles) do
    Enum.any?(needles, &String.contains?(value, &1))
  end

  defp sla_minutes(:critical), do: 15
  defp sla_minutes(:high), do: 60
  defp sla_minutes(:medium), do: 240
  defp sla_minutes(:low), do: 1_440
end
