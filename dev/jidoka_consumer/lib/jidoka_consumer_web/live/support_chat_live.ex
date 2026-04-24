defmodule JidokaConsumerWeb.SupportChatLive do
  use JidokaConsumerWeb, :live_view

  alias JidokaConsumer.Support.DemoData
  alias JidokaConsumerWeb.SupportChatAgentView

  @stream_poll_ms 100
  @chat_timeout_ms 30_000
  @markdown_options [
    extension: [autolink: true, strikethrough: true, table: true, tasklist: true],
    render: [unsafe: false]
  ]
  @impl true
  def mount(_params, session, socket) do
    ticket_queue = seed_ticket_queue()
    {:ok, pid} = SupportChatAgentView.start_agent(session)
    {:ok, view} = SupportChatAgentView.snapshot(pid, session)

    {:ok,
     socket
     |> assign(:agent_pid, pid)
     |> assign(:session, session)
     |> assign(:view, view)
     |> assign(:message, "")
     |> assign(:ticket_queue, ticket_queue)
     |> assign(:example_prompts, DemoData.example_prompts(ticket_queue))
     |> assign(:active_request_id, nil)
     |> assign(:active_run, nil)
     |> assign(:stream_timer_ref, nil)}
  end

  @impl true
  def handle_event("change_message", %{"message" => message}, socket) do
    {:noreply, assign(socket, :message, message)}
  end

  def handle_event("use_example", %{"prompt" => prompt}, socket) do
    {:noreply, assign(socket, :message, prompt)}
  end

  def handle_event("send", %{"message" => message}, socket) do
    case ensure_agent(socket) do
      {:error, reason} ->
        {:noreply, assign_start_error(socket, reason)}

      {:ok, socket} ->
        view = SupportChatAgentView.before_turn(socket.assigns.view, message)
        socket = assign(socket, view: view, message: "")
        request_id = SupportChatAgentView.request_id()

        case start_turn(socket, message, request_id) do
          {:ok, socket, run} ->
            live_view = self()

            {:ok, _pid} =
              Task.Supervisor.start_child(JidokaConsumer.AgentViewTaskSupervisor, fn ->
                result = SupportChatAgentView.await_turn(run, timeout: @chat_timeout_ms)
                send(live_view, {:chat_complete, run.request_id, result})
              end)

            {:noreply,
             socket
             |> assign(active_request_id: run.request_id, active_run: run)
             |> schedule_stream_tick(run.request_id)}

          {:error, reason} ->
            {:noreply, assign_start_error(socket, reason)}
        end
    end
  end

  @impl true
  def handle_info({:stream_tick, request_id}, socket) do
    if socket.assigns.active_request_id == request_id and socket.assigns.active_run do
      case refresh_turn(socket.assigns.active_run, socket.assigns.view) do
        {:ok, view} ->
          {:noreply,
           socket
           |> assign(:view, view)
           |> schedule_stream_tick(request_id)}

        {:error, reason} ->
          view =
            %{
              socket.assigns.view
              | status: :error,
                error: reason,
                error_text: Jidoka.format_error(reason),
                streaming_message: nil
            }

          {:noreply,
           socket
           |> clear_stream_timer()
           |> assign(active_request_id: nil, active_run: nil, view: view)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_info({:chat_complete, request_id, result}, socket) do
    if socket.assigns.active_request_id == request_id and socket.assigns.active_run do
      view =
        case SupportChatAgentView.after_turn(socket.assigns.active_run, result) do
          {:ok, updated_view} ->
            updated_view

          {:error, reason} ->
            %{
              socket.assigns.view
              | status: :error,
                error: reason,
                error_text: Jidoka.format_error(reason),
                streaming_message: nil
            }
        end

      {:noreply,
       socket
       |> clear_stream_timer()
       |> assign(active_request_id: nil, active_run: nil, view: view)
       |> refresh_ticket_queue()}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
    <script src="https://cdn.tailwindcss.com">
    </script>
    <script src="/assets/phoenix/phoenix.min.js">
    </script>
    <script src="/assets/phoenix_live_view/phoenix_live_view.min.js">
    </script>
    <script defer src="/assets/app.js">
    </script>
    <style>
      html, body { background: #f8fafc; color: #0f172a; }
      .markdown-body { overflow-wrap: anywhere; font-size: 0.875rem; line-height: 1.5rem; }
      .markdown-body > :first-child { margin-top: 0; }
      .markdown-body > :last-child { margin-bottom: 0; }
      .markdown-body p { margin: 0.45rem 0; }
      .markdown-body ul, .markdown-body ol { margin: 0.45rem 0 0.45rem 1.2rem; padding-left: 1rem; }
      .markdown-body ul { list-style: disc; }
      .markdown-body ol { list-style: decimal; }
      .markdown-body li { margin: 0.15rem 0; }
      .markdown-body a { color: #0369a1; text-decoration: underline; text-underline-offset: 2px; }
      .markdown-body code { border-radius: 0.35rem; background: #f1f5f9; padding: 0.1rem 0.3rem; color: #0f172a; }
      .markdown-body pre { margin: 0.65rem 0; overflow-x: auto; border-radius: 0.5rem; background: #0f172a; padding: 0.85rem; color: #e2e8f0; }
      .markdown-body pre code { background: transparent; padding: 0; color: inherit; }
      .markdown-body blockquote { margin: 0.65rem 0; border-left: 3px solid #cbd5e1; padding-left: 0.85rem; color: #475569; }
      .markdown-body table { margin: 0.65rem 0; width: 100%; border-collapse: collapse; font-size: 0.8125rem; }
      .markdown-body th, .markdown-body td { border: 1px solid #cbd5e1; padding: 0.35rem 0.5rem; text-align: left; }
      .markdown-body th { background: #f8fafc; font-weight: 600; }
    </style>

    <main class="min-h-screen bg-slate-50 text-slate-950 antialiased">
      <div class="mx-auto flex min-h-screen w-full max-w-7xl flex-col px-4 py-5 sm:px-6 lg:px-8">
        <header class="mb-5 flex flex-col gap-4 border-b border-slate-200 pb-5 lg:flex-row lg:items-end lg:justify-between">
          <div class="space-y-3">
            <div class="flex items-center gap-3">
              <div class="grid h-10 w-10 place-items-center rounded-lg bg-slate-950 text-sm font-semibold text-white shadow-sm">
                J
              </div>
              <div>
                <p class="text-xs font-medium uppercase tracking-wide text-slate-500">
                  Phoenix LiveView
                </p>
                <h1 class="text-2xl font-semibold text-slate-950">Jidoka Support Agent</h1>
              </div>
            </div>
            <p class="max-w-2xl text-sm leading-6 text-slate-600">
              A support console backed by a local consumer-owned Jidoka agent, with chat output,
              ticket tools, workflows, specialists, handoffs, guardrails, and provider context projected separately.
            </p>
          </div>

          <dl class="grid grid-cols-1 gap-2 text-sm sm:grid-cols-3 lg:min-w-[520px]">
            <div class="rounded-lg border border-slate-200 bg-white px-3 py-2 shadow-sm">
              <dt class="text-xs font-medium uppercase text-slate-500">Agent</dt>
              <dd class="mt-1 truncate font-mono text-xs text-slate-800">{@view.agent_id}</dd>
            </div>
            <div class="rounded-lg border border-slate-200 bg-white px-3 py-2 shadow-sm">
              <dt class="text-xs font-medium uppercase text-slate-500">Conversation</dt>
              <dd class="mt-1 truncate font-mono text-xs text-slate-800">{@view.conversation_id}</dd>
            </div>
            <div class="rounded-lg border border-slate-200 bg-white px-3 py-2 shadow-sm">
              <dt class="text-xs font-medium uppercase text-slate-500">Status</dt>
              <dd class="mt-1">
                <span class={[
                  "inline-flex items-center rounded-full px-2 py-1 text-xs font-medium ring-1 ring-inset",
                  status_badge_class(@view.status)
                ]}>
                  {@view.status}
                </span>
              </dd>
            </div>
          </dl>
        </header>

        <div class="grid flex-1 gap-5 lg:grid-cols-[minmax(0,1fr)_420px]">
          <section class="flex min-h-[680px] flex-col overflow-hidden rounded-lg border border-slate-200 bg-white shadow-sm">
            <div class="border-b border-slate-200 px-5 py-4">
              <h2 class="text-base font-semibold text-slate-950">Visible Messages</h2>
              <p class="mt-1 text-sm text-slate-600">User-facing transcript rendered from the agent view.</p>
            </div>

            <div class="border-b border-slate-200 bg-slate-50 px-5 py-4">
              <div class="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
                <h3 class="text-sm font-semibold text-slate-900">Try a support path</h3>
                <p class="text-xs text-slate-500">Populates the message box without sending.</p>
              </div>
              <div class="mt-3 flex flex-wrap gap-2">
                <button
                  :for={example <- @example_prompts}
                  type="button"
                  phx-click="use_example"
                  phx-value-prompt={example.prompt}
                  disabled={@view.status == :running}
                  class="inline-flex min-h-10 items-center gap-2 rounded-lg border border-slate-200 bg-white px-3 py-2 text-left text-xs shadow-sm transition hover:border-slate-300 hover:bg-slate-50 focus:outline-none focus:ring-4 focus:ring-sky-100 disabled:cursor-not-allowed disabled:opacity-60"
                >
                  <span class="flex flex-col">
                    <span class="font-medium text-slate-900">{example.label}</span>
                    <span class="mt-0.5 text-[11px] text-slate-500">{example.route}</span>
                  </span>
                  <span class="rounded-full bg-slate-100 px-2 py-0.5 font-medium text-slate-500">{example.detail}</span>
                </button>
              </div>
            </div>

            <div id="visible-messages" class="flex-1 space-y-4 overflow-y-auto px-5 py-5">
              <div
                :if={visible_messages(@view) == []}
                class="flex h-full min-h-[360px] items-center justify-center rounded-lg border border-dashed border-slate-300 bg-slate-50 px-6 text-center"
              >
                <div class="max-w-[240px]">
                  <p class="text-sm font-medium text-slate-800">No messages yet</p>
                  <p class="mt-1 text-sm leading-6 text-slate-500">
                    Send a support request to start the conversation.
                  </p>
                </div>
              </div>

              <article
                :for={message <- visible_messages(@view)}
                class={["flex", message_row_class(message.role)]}
              >
                <div class={[
                  "max-w-[82%] rounded-lg px-4 py-3 shadow-sm ring-1 ring-inset",
                  message_bubble_class(message.role)
                ]}>
                  <div class="mb-1 flex items-center gap-2">
                    <span class={[
                      "rounded-full px-2 py-0.5 text-[11px] font-medium uppercase",
                      message_role_class(message.role)
                    ]}>
                      {role_label(message.role)}
                    </span>
                    <span :if={Map.get(message, :pending?)} class="text-xs text-slate-400">
                      pending
                    </span>
                    <span :if={Map.get(message, :streaming?)} class="text-xs text-sky-500">
                      streaming
                    </span>
                  </div>
                  <div :if={markdown_message?(message)} class="markdown-body">
                    {markdown_content(message.content)}
                  </div>
                  <p :if={!markdown_message?(message)} class="whitespace-pre-wrap text-sm leading-6">
                    {message.content}
                  </p>
                </div>
              </article>
            </div>

            <form class="border-t border-slate-200 bg-slate-50 p-4" phx-change="change_message" phx-submit="send">
              <label for="message" class="sr-only">Message</label>
              <div class="flex flex-col gap-3 sm:flex-row sm:items-end">
                <textarea
                  id="message"
                  name="message"
                  rows="3"
                  class="min-h-[92px] flex-1 resize-y rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm leading-6 text-slate-950 shadow-sm outline-none transition placeholder:text-slate-400 focus:border-sky-500 focus:ring-4 focus:ring-sky-100"
                  placeholder="Ask for refund review, ticket work, specialist delegation, handoff, or guardrail behavior..."
                >{@message}</textarea>
                <button
                  type="submit"
                  class="inline-flex h-10 items-center justify-center rounded-lg bg-slate-950 px-4 text-sm font-medium text-white shadow-sm transition hover:bg-slate-800 focus:outline-none focus:ring-4 focus:ring-slate-200 disabled:cursor-not-allowed disabled:bg-slate-400"
                  disabled={@view.status == :running}
                  phx-disable-with="Sending..."
                >
                  Send
                </button>
              </div>
            </form>
          </section>

          <aside class="space-y-4">
            <p
              :if={@view.error_text}
              class="rounded-lg border border-rose-200 bg-rose-50 px-4 py-3 text-sm leading-6 text-rose-800 shadow-sm"
            >
              {@view.error_text}
            </p>

            <section class="overflow-hidden rounded-lg border border-slate-200 bg-white shadow-sm">
              <div class="border-b border-slate-200 px-4 py-3">
                <h2 class="text-sm font-semibold text-slate-950">Demo Ticket Queue</h2>
                <p class="mt-1 text-xs leading-5 text-slate-500">Seeded ETS tickets plus tickets created by this session.</p>
              </div>
              <div class="max-h-80 space-y-3 overflow-y-auto p-4">
                <p :if={@ticket_queue == []} class="text-sm text-slate-500">
                  No demo tickets are loaded.
                </p>
                <article :for={ticket <- @ticket_queue} class="rounded-lg bg-slate-50 p-3 ring-1 ring-slate-200">
                  <div class="flex items-start justify-between gap-3">
                    <div class="min-w-0">
                      <h3 class="truncate text-sm font-semibold text-slate-900">{ticket.subject}</h3>
                      <p class="mt-1 truncate font-mono text-[11px] text-slate-500">
                        {short_id(ticket.id)} · {ticket.customer_id} · {ticket.order_id || "no order"}
                      </p>
                    </div>
                    <span class={[
                      "shrink-0 rounded-full px-2 py-0.5 text-[11px] font-medium ring-1 ring-inset",
                      ticket_priority_class(ticket.priority)
                    ]}>
                      {ticket.priority}
                    </span>
                  </div>
                  <div class="mt-2 flex flex-wrap gap-1.5">
                    <span class={[
                      "rounded-full px-2 py-0.5 text-[11px] font-medium ring-1 ring-inset",
                      ticket_status_class(ticket.status)
                    ]}>
                      {ticket.status}
                    </span>
                    <span class="rounded-full bg-white px-2 py-0.5 text-[11px] font-medium text-slate-500 ring-1 ring-slate-200">
                      {ticket.assignee}
                    </span>
                  </div>
                  <button
                    type="button"
                    phx-click="use_example"
                    phx-value-prompt={ticket.prompt}
                    disabled={@view.status == :running}
                    class="mt-3 inline-flex h-8 items-center rounded-md border border-slate-200 bg-white px-2.5 text-xs font-medium text-slate-700 shadow-sm transition hover:border-slate-300 hover:bg-slate-50 disabled:cursor-not-allowed disabled:opacity-60"
                  >
                    Ask about ticket
                  </button>
                </article>
              </div>
            </section>

            <section class="overflow-hidden rounded-lg border border-slate-200 bg-white shadow-sm">
              <div class="border-b border-slate-200 px-4 py-3">
                <h2 class="text-sm font-semibold text-slate-950">Turn Summary</h2>
                <p class="mt-1 text-xs leading-5 text-slate-500">Current request and conversation state.</p>
              </div>
              <dl class="grid grid-cols-2 gap-3 p-4 text-xs">
                <div class="rounded-lg bg-slate-50 p-3 ring-1 ring-slate-200">
                  <dt class="font-medium uppercase text-slate-500">Request</dt>
                  <dd class="mt-1 truncate font-mono text-slate-800">{summary_request_id(@view)}</dd>
                </div>
                <div class="rounded-lg bg-slate-50 p-3 ring-1 ring-slate-200">
                  <dt class="font-medium uppercase text-slate-500">Model</dt>
                  <dd class="mt-1 truncate text-slate-800">{summary_model(@view)}</dd>
                </div>
                <div class="rounded-lg bg-slate-50 p-3 ring-1 ring-slate-200">
                  <dt class="font-medium uppercase text-slate-500">Duration</dt>
                  <dd class="mt-1 text-slate-800">{summary_duration(@view)}</dd>
                </div>
                <div class="rounded-lg bg-slate-50 p-3 ring-1 ring-slate-200">
                  <dt class="font-medium uppercase text-slate-500">Usage</dt>
                  <dd class="mt-1 truncate text-slate-800">{summary_usage(@view)}</dd>
                </div>
                <div class="col-span-2 rounded-lg bg-slate-50 p-3 ring-1 ring-slate-200">
                  <dt class="font-medium uppercase text-slate-500">Conversation Owner</dt>
                  <dd class="mt-1 truncate font-mono text-slate-800">{summary_owner(@view)}</dd>
                </div>
              </dl>
            </section>

            <section class="overflow-hidden rounded-lg border border-slate-200 bg-white shadow-sm">
              <div class="border-b border-slate-200 px-4 py-3">
                <h2 class="text-sm font-semibold text-slate-950">Run Trace</h2>
                <p class="mt-1 text-xs leading-5 text-slate-500">Semantic runtime path for the current turn.</p>
              </div>
              <ol id="run-trace" class="max-h-[28rem] space-y-3 overflow-y-auto p-4">
                <li :if={run_trace(@view) == []} class="text-sm text-slate-500">No runtime trace yet.</li>
                <li :for={trace <- run_trace(@view)} class="rounded-lg bg-slate-50 p-3 ring-1 ring-slate-200">
                  <div class="flex items-start gap-3">
                    <span class={["mt-1 h-2.5 w-2.5 shrink-0 rounded-full", trace_dot_class(trace.status)]}></span>
                    <div class="min-w-0 flex-1">
                      <div class="flex flex-wrap items-center gap-2">
                        <h3 class="text-sm font-semibold text-slate-900">{trace.title}</h3>
                        <span class={[
                          "rounded-full px-2 py-0.5 text-[11px] font-medium ring-1 ring-inset",
                          trace_badge_class(trace.status)
                        ]}>
                          {trace.status}
                        </span>
                      </div>
                      <p :if={trace.target} class="mt-1 truncate font-mono text-xs text-slate-500">{trace.target}</p>
                      <p class="mt-2 text-xs leading-5 text-slate-700">{trace.summary}</p>
                      <div :if={trace.meta != []} class="mt-2 flex flex-wrap gap-1.5">
                        <span
                          :for={item <- trace.meta}
                          class="rounded-full bg-white px-2 py-0.5 text-[11px] font-medium text-slate-500 ring-1 ring-slate-200"
                        >
                          {item}
                        </span>
                      </div>
                      <details :if={trace.raw} class="mt-2">
                        <summary class="cursor-pointer text-xs font-medium text-slate-500">Raw payload</summary>
                        <pre class="mt-2 max-h-48 overflow-auto rounded-md bg-slate-950 p-3 text-[11px] leading-5 text-slate-100">{inspect(trace.raw, pretty: true)}</pre>
                      </details>
                    </div>
                  </div>
                </li>
              </ol>
            </section>

            <section class="overflow-hidden rounded-lg border border-slate-200 bg-white shadow-sm">
              <div class="border-b border-slate-200 px-4 py-3">
                <h2 class="text-sm font-semibold text-slate-950">LLM Context</h2>
                <p class="mt-1 text-xs leading-5 text-slate-500">Provider-facing messages, separated from visible chat.</p>
              </div>
              <ol id="llm-context" class="max-h-72 space-y-3 overflow-y-auto p-4">
                <li :if={llm_context_messages(@view) == []} class="text-sm text-slate-500">
                  No LLM context yet.
                </li>
                <li :for={message <- llm_context_messages(@view)} class="rounded-lg bg-slate-50 p-3 ring-1 ring-slate-200">
                  <div class="flex items-center justify-between gap-2">
                    <code class="text-xs font-semibold text-slate-700">{message.seq}: {message.role}</code>
                    <div class="flex shrink-0 flex-wrap justify-end gap-1.5">
                      <span :if={message.role == :system} class="rounded-full bg-violet-50 px-2 py-0.5 text-[11px] font-medium text-violet-700 ring-1 ring-violet-100">
                        system prompt
                      </span>
                      <span :if={llm_tool_count(message) > 0} class="rounded-full bg-sky-50 px-2 py-0.5 text-[11px] font-medium text-sky-700 ring-1 ring-sky-100">
                        {llm_tool_count(message)} tool call(s)
                      </span>
                    </div>
                  </div>
                  <p class="mt-2 text-xs leading-5 text-slate-600">{llm_message_preview(message)}</p>
                  <details class="mt-2">
                    <summary class="cursor-pointer text-xs font-medium text-slate-500">Raw message</summary>
                    <pre class="mt-2 max-h-48 overflow-auto rounded-md bg-slate-950 p-3 text-[11px] leading-5 text-slate-100">{inspect(message, pretty: true)}</pre>
                  </details>
                </li>
              </ol>
            </section>

            <section class="overflow-hidden rounded-lg border border-slate-200 bg-white shadow-sm">
              <div class="border-b border-slate-200 px-4 py-3">
                <h2 class="text-sm font-semibold text-slate-950">Runtime Context</h2>
                <p class="mt-1 text-xs leading-5 text-slate-500">Public context projected into this turn.</p>
              </div>
              <dl class="grid grid-cols-1 gap-2 p-4 text-xs">
                <div :for={{key, value} <- runtime_context_items(@view.runtime_context)} class="rounded-lg bg-slate-50 p-3 ring-1 ring-slate-200">
                  <dt class="font-mono font-semibold text-slate-700">{key}</dt>
                  <dd class="mt-1 truncate text-slate-600">{value}</dd>
                </div>
              </dl>
            </section>
          </aside>
        </div>
      </div>
    </main>
    """
  end

  defp status_badge_class(:idle), do: "bg-emerald-50 text-emerald-700 ring-emerald-200"
  defp status_badge_class(:running), do: "bg-amber-50 text-amber-700 ring-amber-200"
  defp status_badge_class(:error), do: "bg-rose-50 text-rose-700 ring-rose-200"
  defp status_badge_class(:interrupted), do: "bg-violet-50 text-violet-700 ring-violet-200"
  defp status_badge_class(:handoff), do: "bg-sky-50 text-sky-700 ring-sky-200"
  defp status_badge_class(_status), do: "bg-slate-100 text-slate-700 ring-slate-200"

  defp trace_dot_class(:ok), do: "bg-emerald-500"
  defp trace_dot_class(:running), do: "bg-amber-500"
  defp trace_dot_class(:blocked), do: "bg-rose-500"
  defp trace_dot_class(:error), do: "bg-rose-500"
  defp trace_dot_class(:handoff), do: "bg-sky-500"
  defp trace_dot_class(_status), do: "bg-slate-400"

  defp trace_badge_class(:ok), do: "bg-emerald-50 text-emerald-700 ring-emerald-200"
  defp trace_badge_class(:running), do: "bg-amber-50 text-amber-700 ring-amber-200"
  defp trace_badge_class(:blocked), do: "bg-rose-50 text-rose-700 ring-rose-200"
  defp trace_badge_class(:error), do: "bg-rose-50 text-rose-700 ring-rose-200"
  defp trace_badge_class(:handoff), do: "bg-sky-50 text-sky-700 ring-sky-200"
  defp trace_badge_class(_status), do: "bg-slate-100 text-slate-700 ring-slate-200"

  defp schedule_stream_tick(socket, request_id) do
    socket = clear_stream_timer(socket)
    ref = Process.send_after(self(), {:stream_tick, request_id}, @stream_poll_ms)
    assign(socket, :stream_timer_ref, ref)
  end

  defp clear_stream_timer(socket) do
    case socket.assigns[:stream_timer_ref] do
      nil ->
        socket

      ref ->
        Process.cancel_timer(ref)
        assign(socket, :stream_timer_ref, nil)
    end
  end

  defp seed_ticket_queue do
    case DemoData.ensure_seeded() do
      {:ok, tickets} -> tickets
      {:error, _reason} -> []
    end
  end

  defp refresh_ticket_queue(socket) do
    ticket_queue = DemoData.ticket_queue_or_empty()

    socket
    |> assign(:ticket_queue, ticket_queue)
    |> assign(:example_prompts, DemoData.example_prompts(ticket_queue))
  end

  defp ensure_agent(socket) do
    case socket.assigns[:agent_pid] do
      pid when is_pid(pid) ->
        if Process.alive?(pid), do: {:ok, socket}, else: restart_agent(socket)

      _other ->
        restart_agent(socket)
    end
  end

  defp restart_agent(socket) do
    with {:ok, pid} <- SupportChatAgentView.start_agent(socket.assigns.session),
         {:ok, view} <- SupportChatAgentView.snapshot(pid, socket.assigns.session) do
      {:ok,
       socket
       |> assign(:agent_pid, pid)
       |> assign(:view, view)}
    end
  end

  defp start_turn(socket, message, request_id) do
    case do_start_turn(socket, message, request_id) do
      {:ok, run} -> {:ok, socket, run}
      {:error, _reason} = error -> error
    end
  catch
    :exit, _reason ->
      with {:ok, socket} <- restart_agent(socket) do
        case do_start_turn(socket, message, request_id) do
          {:ok, run} -> {:ok, socket, run}
          {:error, _reason} = error -> error
        end
      else
        {:error, restart_reason} -> {:error, restart_reason}
      end
  end

  defp do_start_turn(socket, message, request_id) do
    SupportChatAgentView.start_turn(
      socket.assigns.agent_pid,
      message,
      socket.assigns.session,
      request_id: request_id,
      timeout: @chat_timeout_ms
    )
  end

  defp refresh_turn(run, view) do
    SupportChatAgentView.refresh_turn(run, view)
  catch
    :exit, reason ->
      {:error,
       Jidoka.Error.execution_error("Agent process stopped while refreshing the chat view.",
         details: %{cause: reason}
       )}
  end

  defp assign_start_error(socket, reason) do
    view = %{
      socket.assigns.view
      | status: :error,
        error: reason,
        error_text: Jidoka.format_error(reason),
        streaming_message: nil
    }

    assign(socket, :view, view)
  end

  defp visible_messages(view) do
    view
    |> SupportChatAgentView.visible_messages()
    |> Enum.reject(&internal_assistant_narration?/1)
  end

  defp internal_assistant_narration?(%{role: :assistant, content: content})
       when is_binary(content) do
    content
    |> String.downcase()
    |> String.match?(
      ~r/\b(now i['’]?ll|i['’]?ll|i will|next, i)\b.*\b(call|create|run|use|invoke)\b/
    )
  end

  defp internal_assistant_narration?(_message), do: false

  defp message_row_class(:user), do: "justify-end"
  defp message_row_class(_role), do: "justify-start"

  defp message_bubble_class(:user), do: "bg-slate-950 text-white ring-slate-950"
  defp message_bubble_class(:assistant), do: "bg-white text-slate-900 ring-slate-200"
  defp message_bubble_class(_role), do: "bg-slate-50 text-slate-900 ring-slate-200"

  defp message_role_class(:user), do: "bg-white/10 text-white"
  defp message_role_class(:assistant), do: "bg-sky-50 text-sky-700"
  defp message_role_class(_role), do: "bg-slate-200 text-slate-700"

  defp ticket_priority_class("high"), do: "bg-rose-50 text-rose-700 ring-rose-200"
  defp ticket_priority_class("normal"), do: "bg-amber-50 text-amber-700 ring-amber-200"
  defp ticket_priority_class(_priority), do: "bg-slate-100 text-slate-700 ring-slate-200"

  defp ticket_status_class("open"), do: "bg-sky-50 text-sky-700 ring-sky-200"
  defp ticket_status_class("escalated"), do: "bg-violet-50 text-violet-700 ring-violet-200"
  defp ticket_status_class("resolved"), do: "bg-emerald-50 text-emerald-700 ring-emerald-200"
  defp ticket_status_class(_status), do: "bg-slate-100 text-slate-700 ring-slate-200"

  defp short_id(nil), do: "no id"
  defp short_id(id) when is_binary(id) and byte_size(id) > 8, do: String.slice(id, 0, 8)
  defp short_id(id), do: to_string(id)

  defp markdown_message?(%{role: role}) when role in [:assistant, :system], do: true
  defp markdown_message?(_message), do: false

  defp markdown_content(content) when is_binary(content) do
    content
    |> normalize_support_ticket_markdown()
    |> MDEx.to_html!(@markdown_options)
    |> Phoenix.HTML.raw()
  rescue
    _error -> content
  end

  defp markdown_content(content), do: content

  defp normalize_support_ticket_markdown(content) do
    cond do
      String.contains?(content, "Support ticket created successfully") and
          String.contains?(content, "**Ticket ID:**") ->
        content
        |> String.replace(
          ~r/Support ticket created successfully[.!]?\s+-\s+/,
          "Support ticket created successfully.\n\n- "
        )
        |> String.replace(
          ~r/\s+-\s+\*\*(Customer|Order|Priority|Status|Issue):\*\*/,
          "\n- **\\1:**"
        )
        |> String.replace(~r/\s+(The ticket is now open and ready for assignment\.?)/, "\n\n\\1")

      String.contains?(content, "**Ticket Details:**") and
          String.contains?(content, "**Ticket ID:**") ->
        content
        |> String.replace(~r/\*\*Ticket Details:\*\*\s+-\s+/, "**Ticket Details:**\n\n- ")
        |> String.replace(
          ~r/\s+-\s+\*\*(Ticket ID|Customer|Order|Priority|Status|Subject|Assignee|Issue):\*\*/,
          "\n- **\\1:**"
        )
        |> String.replace(
          ~r/\s+---\s+\*\*(Why This Needs Follow-Up|Recommended Next Owner):\*\*/,
          "\n\n**\\1:**\n\n"
        )
        |> String.replace(
          ~r/\s+\*\*(Why This Needs Follow-Up|Recommended Next Owner):\*\*/,
          "\n\n**\\1:**\n\n"
        )
        |> String.replace(~r/\s+(\d+)\.\s+/, "\n\\1. ")

      true ->
        content
    end
  end

  defp summary_request_id(view) do
    case request_summary(view) do
      %{request_id: request_id} when is_binary(request_id) and request_id != "" -> request_id
      _ -> last_request_id(view) || "not started"
    end
  end

  defp summary_model(view) do
    case request_summary(view) do
      %{model: model} when not is_nil(model) -> short_text(model, 36)
      _ -> "not selected"
    end
  end

  defp summary_duration(view) do
    case request_summary(view) do
      %{duration_ms: duration_ms} when is_integer(duration_ms) -> "#{duration_ms} ms"
      _ when view.status == :running -> "running"
      _ -> "not available"
    end
  end

  defp summary_usage(view) do
    case request_summary(view) do
      %{usage: %{input: input, output: output, cost: cost}} ->
        ["in #{format_count(input)}", "out #{format_count(output)}", format_cost(cost)]
        |> Enum.reject(&(&1 == ""))
        |> Enum.join(" / ")

      _ ->
        "not reported"
    end
  end

  defp summary_owner(view) do
    case owner_summary(view) do
      %{agent_id: agent_id} when is_binary(agent_id) and agent_id != "" -> "#{agent_id} (handoff)"
      _ -> view.agent_id
    end
  end

  defp run_trace(view) do
    summary = request_summary(view)

    []
    |> maybe_append(input_trace(view, summary))
    |> maybe_append(context_trace(view, summary))
    |> Kernel.++(capability_trace(summary, view.events))
    |> Kernel.++(response_trace(view))
  end

  defp input_trace(view, summary) do
    case current_user_message(view, summary) do
      nil ->
        nil

      message ->
        %{
          title: "Input received",
          status: if(view.status == :running, do: :running, else: :ok),
          target: "support_router_agent",
          summary: short_text(message, 180),
          meta: ["conversation #{view.conversation_id}"],
          raw: nil
        }
    end
  end

  defp context_trace(view, _summary) do
    cond do
      guardrail_blocked?(view) ->
        %{
          title: "Policy blocked",
          status: :blocked,
          target: "support_sensitive_data",
          summary: view.error_text,
          meta: ["blocked before model call"],
          raw: view.error
        }

      current_user_message(view, nil) ->
        %{
          title: "Support context prepared",
          status: :ok,
          target: "JidokaConsumer.Support.Agents.SupportRouterAgent",
          summary:
            "Phoenix session context and the support actor were attached before ticket tools, workflows, and specialists can run.",
          meta: ["Ash actor", "tickets", "workflows", "specialists"],
          raw: view.runtime_context
        }

      true ->
        nil
    end
  end

  defp capability_trace(nil, events), do: event_trace(events)

  defp capability_trace(summary, events) when is_map(summary) do
    summary_traces =
      workflow_traces(Map.get(summary, :workflows, [])) ++
        subagent_traces(Map.get(summary, :subagents, [])) ++
        handoff_traces(Map.get(summary, :handoffs, []))

    if summary_traces == [], do: event_trace(events), else: summary_traces
  end

  defp workflow_traces(calls) when is_list(calls) do
    Enum.map(calls, fn call ->
      %{
        title: "Workflow ran",
        status: outcome_status(Map.get(call, :outcome)),
        target: "#{Map.get(call, :name, "workflow")} -> #{module_name(Map.get(call, :workflow))}",
        summary:
          Map.get(call, :output_preview) ||
            "The agent used a deterministic workflow for this step.",
        meta:
          [
            format_duration(Map.get(call, :duration_ms)),
            format_keys("input", Map.get(call, :input_keys, [])),
            format_keys("context", Map.get(call, :context_keys, []))
          ]
          |> compact_list(),
        raw: call
      }
    end)
  end

  defp workflow_traces(_calls), do: []

  defp subagent_traces(calls) when is_list(calls) do
    Enum.map(calls, fn call ->
      %{
        title: "Subagent delegated",
        status: outcome_status(Map.get(call, :outcome)),
        target: "#{Map.get(call, :name, "subagent")} -> #{module_name(Map.get(call, :agent))}",
        summary:
          Map.get(call, :result_preview) ||
            Map.get(call, :task_preview) ||
            "The router delegated a bounded task while keeping control of the turn.",
        meta:
          [
            format_duration(Map.get(call, :duration_ms)),
            format_keys("context", Map.get(call, :context_keys, [])),
            "mode #{Map.get(call, :mode, :unknown)}"
          ]
          |> compact_list(),
        raw: call
      }
    end)
  end

  defp subagent_traces(_calls), do: []

  defp handoff_traces(calls) when is_list(calls) do
    Enum.map(calls, fn call ->
      %{
        title: "Conversation handed off",
        status: outcome_status(Map.get(call, :outcome)),
        target:
          "#{Map.get(call, :name, "handoff")} -> #{Map.get(call, :to_agent_id, "target agent")}",
        summary:
          Map.get(call, :summary_preview) ||
            Map.get(call, :message_preview) ||
            "Conversation ownership moved to another agent.",
        meta:
          [
            format_duration(Map.get(call, :duration_ms)),
            "owner #{Map.get(call, :to_agent_id, "unknown")}",
            format_keys("context", Map.get(call, :context_keys, []))
          ]
          |> compact_list(),
        raw: call
      }
    end)
  end

  defp handoff_traces(_calls), do: []

  defp event_trace(events) when is_list(events) do
    Enum.map(events, fn event ->
      payload = Map.get(event, :payload, %{})

      %{
        title: event_title(event),
        status: :ok,
        target: Map.get(payload, :name) || Map.get(payload, "name") || Map.get(event, :label),
        summary: event_summary(event),
        meta: ["thread seq #{Map.get(event, :seq, "?")}"],
        raw: payload
      }
    end)
  end

  defp event_trace(_events), do: []

  defp response_trace(view) do
    cond do
      is_map(view.streaming_message) ->
        [
          %{
            title: "Assistant streaming",
            status: :running,
            target: view.agent_id,
            summary: short_text(Map.get(view.streaming_message, :content), 180),
            meta: ["visible message"],
            raw: view.streaming_message
          }
        ]

      assistant = latest_visible_message(view, :assistant) ->
        [
          %{
            title: "Assistant responded",
            status: :ok,
            target: view.agent_id,
            summary: short_text(Map.get(assistant, :content), 180),
            meta: ["visible message"],
            raw: nil
          }
        ]

      true ->
        []
    end
  end

  defp llm_context_messages(view) do
    messages = Map.get(view, :llm_context, [])

    case system_context_message(view) do
      nil -> messages
      system_message -> [system_message | Enum.reject(messages, &(Map.get(&1, :role) == :system))]
    end
  end

  defp system_context_message(view) do
    if guardrail_blocked?(view) do
      nil
    else
      system_context_message_from_summary(view)
    end
  end

  defp system_context_message_from_summary(view) do
    case request_summary(view) do
      %{system_prompt: system_prompt} = summary
      when is_binary(system_prompt) and system_prompt != "" ->
        request_id = Map.get(summary, :request_id)

        %{
          id: "system-" <> (request_id || view.conversation_id),
          seq: "system",
          role: :system,
          content: system_prompt,
          context_ref: "system",
          request_id: request_id,
          run_id: request_id,
          source: :request_summary
        }

      _ ->
        nil
    end
  end

  defp llm_tool_count(message) do
    case Map.get(message, :tool_calls) do
      calls when is_list(calls) -> length(calls)
      _ -> 0
    end
  end

  defp llm_message_preview(%{content: content} = message)
       when is_binary(content) and content != "" do
    short_text(content, 180)
    |> case do
      "" -> llm_fallback_preview(message)
      preview -> preview
    end
  end

  defp llm_message_preview(message), do: llm_fallback_preview(message)

  defp llm_fallback_preview(message) do
    case Map.get(message, :tool_calls, []) do
      calls when is_list(calls) and calls != [] ->
        names =
          calls
          |> Enum.map(&(Map.get(&1, :name) || Map.get(&1, "name") || "tool"))
          |> Enum.join(", ")

        "Requested tool call(s): #{names}"

      _ ->
        "No text content."
    end
  end

  defp runtime_context_items(context) when is_map(context) do
    context
    |> Enum.map(fn {key, value} -> {to_string(key), short_text(value, 90)} end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp runtime_context_items(_context), do: []

  defp request_summary(%{metadata: %{request_summary: summary}}) when is_map(summary), do: summary

  defp request_summary(%{metadata: %{"request_summary" => summary}}) when is_map(summary),
    do: summary

  defp request_summary(_view), do: nil

  defp owner_summary(%{metadata: %{handoff_owner: owner}}) when is_map(owner), do: owner
  defp owner_summary(%{metadata: %{"handoff_owner" => owner}}) when is_map(owner), do: owner
  defp owner_summary(_view), do: nil

  defp current_user_message(_view, %{user_message: message})
       when is_binary(message) and message != "", do: message

  defp current_user_message(_view, %{input_message: message})
       when is_binary(message) and message != "", do: message

  defp current_user_message(view, _summary),
    do: latest_visible_message(view, :user) |> message_content()

  defp latest_visible_message(view, role) do
    view
    |> visible_messages()
    |> Enum.reverse()
    |> Enum.find(&(Map.get(&1, :role) == role))
  end

  defp message_content(%{content: content}) when is_binary(content) and content != "", do: content
  defp message_content(_message), do: nil

  defp guardrail_blocked?(%{error_text: error_text}) when is_binary(error_text) do
    error_text
    |> String.downcase()
    |> String.contains?("guardrail")
  end

  defp guardrail_blocked?(_view), do: false

  defp last_request_id(view) do
    [view.streaming_message | Enum.reverse(view.llm_context ++ view.visible_messages)]
    |> Enum.find_value(fn
      %{request_id: request_id} when is_binary(request_id) and request_id != "" -> request_id
      _ -> nil
    end)
  end

  defp event_title(%{kind: :tool_call}), do: "Capability requested"
  defp event_title(%{kind: :tool_result}), do: "Capability returned"
  defp event_title(%{kind: :context_operation}), do: "Context updated"
  defp event_title(%{label: label}) when is_binary(label), do: label
  defp event_title(_event), do: "Runtime event"

  defp event_summary(%{kind: :tool_call, payload: payload}) do
    "The model selected #{Map.get(payload, :name) || Map.get(payload, "name") || "a capability"} for execution."
  end

  defp event_summary(%{kind: :tool_result, payload: payload}) do
    payload
    |> Map.get(:content, Map.get(payload, "content", "The capability returned a result."))
    |> short_text(180)
  end

  defp event_summary(%{kind: :context_operation}),
    do: "The agent thread recorded a context operation."

  defp event_summary(_event), do: "The agent runtime recorded an event."

  defp outcome_status({:error, _reason}), do: :error
  defp outcome_status(:handoff), do: :handoff
  defp outcome_status(:ok), do: :ok
  defp outcome_status(nil), do: :ok
  defp outcome_status(_outcome), do: :ok

  defp module_name(module) when is_atom(module) do
    module
    |> inspect()
    |> String.replace_prefix("Elixir.", "")
  end

  defp module_name(nil), do: "unknown"
  defp module_name(other), do: short_text(other, 64)

  defp format_duration(duration_ms) when is_integer(duration_ms), do: "#{duration_ms} ms"
  defp format_duration(_duration_ms), do: nil

  defp format_keys(label, keys) when is_list(keys) and keys != [] do
    "#{label} #{Enum.join(keys, ", ")}"
  end

  defp format_keys(_label, _keys), do: nil

  defp format_count(value) when is_integer(value), do: Integer.to_string(value)
  defp format_count(nil), do: "-"
  defp format_count(value), do: to_string(value)

  defp format_cost(cost) when is_number(cost),
    do: "$#{:erlang.float_to_binary(cost * 1.0, decimals: 4)}"

  defp format_cost(_cost), do: ""

  defp compact_list(items), do: Enum.reject(items, &(&1 in [nil, ""]))

  defp maybe_append(items, nil), do: items
  defp maybe_append(items, item), do: items ++ [item]

  defp short_text(value, limit) when is_integer(limit) do
    value
    |> normalize_text()
    |> case do
      text ->
        if String.length(text) > limit, do: String.slice(text, 0, limit) <> "...", else: text
    end
  end

  defp normalize_text(nil), do: ""

  defp normalize_text(value) when is_binary(value),
    do: value |> String.replace(~r/\s+/, " ") |> String.trim()

  defp normalize_text(value),
    do: value |> inspect(limit: 8, printable_limit: 180) |> normalize_text()

  defp role_label(role) do
    role
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
