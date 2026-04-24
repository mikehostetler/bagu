defmodule JidokaConsumerWeb.SupportChatLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint JidokaConsumerWeb.Endpoint

  test "renders separate visible message and LLM context panels" do
    {:ok, _view, html} =
      build_conn()
      |> init_test_session(%{"conversation_id" => "live-view-test"})
      |> live("/")

    assert html =~ "Jidoka Support Agent"
    assert html =~ "Visible Messages"
    assert html =~ "Demo Ticket Queue"
    assert html =~ "Turn Summary"
    assert html =~ "Run Trace"
    assert html =~ "LLM Context"
    assert html =~ "Runtime Context"
    assert html =~ "/assets/app.js"
    assert html =~ "consumer-support-liveview-live_view_test"
    assert html =~ "ticket tools, workflows, specialists, handoffs, guardrails"
  end

  test "example prompt buttons prefill the composer" do
    {:ok, view, html} =
      build_conn()
      |> init_test_session(%{"conversation_id" => "live-view-prompts-test"})
      |> live("/")

    assert html =~ "Try a support path"
    assert html =~ "Process damaged refund"
    assert html =~ "List ticket queue"
    assert html =~ "Escalate seeded ticket"
    assert html =~ "Transfer to billing"
    assert html =~ "Blocked sensitive data"

    prompt =
      "Process a damaged-arrival refund for account acct_vip and order ord_damaged. The customer says it arrived broken and wants a refund."

    html = render_click(view, "use_example", %{"prompt" => prompt})

    assert html =~ prompt
  end

  test "rejects empty submissions locally without LLM context" do
    {:ok, view, _html} =
      build_conn()
      |> init_test_session(%{"conversation_id" => "live-view-empty-message-test"})
      |> live("/")

    html = render_submit(view, "send", %{"message" => "   "})

    assert html =~ "Message must not be empty."
    assert html =~ "No LLM context yet."
  end
end
