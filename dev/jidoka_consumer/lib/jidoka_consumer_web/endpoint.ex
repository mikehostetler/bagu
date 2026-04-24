defmodule JidokaConsumerWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :jidoka_consumer

  @session_options [
    store: :cookie,
    key: "_jidoka_consumer_key",
    signing_salt: "jidoka-live-view"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: false

  plug Plug.Static,
    at: "/assets/phoenix",
    from: {:phoenix, "priv/static"},
    only: ~w(phoenix.min.js)

  plug Plug.Static,
    at: "/assets/phoenix_live_view",
    from: {:phoenix_live_view, "priv/static"},
    only: ~w(phoenix_live_view.min.js)

  plug Plug.Static,
    at: "/assets",
    from: :jidoka_consumer,
    only: ~w(app.js)

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug JidokaConsumerWeb.Router
end
