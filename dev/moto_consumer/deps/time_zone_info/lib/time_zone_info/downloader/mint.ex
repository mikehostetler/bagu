if Code.ensure_loaded?(Mint.HTTP) do
  defmodule TimeZoneInfo.Downloader.Mint do
    @moduledoc """
    An implementation of the `TimeZoneInfo.Downloader` behaviour using `Mint`.
    """

    @behaviour TimeZoneInfo.Downloader

    alias Mint.HTTP

    @impl true
    def download(uri, opts) do
      method = "GET"
      headers = opts[:headers] || []
      http = http!()

      with {:ok, conn} <- http.connect(scheme(uri), uri.host, uri.port),
           {:ok, conn, request_ref} <- http.request(conn, method, path(uri), headers, ""),
           {:ok, conn, body} <- receive_response(conn, request_ref),
           {:ok, _conn} <- http.close(conn) do
        {:ok, body}
      else
        error -> {:error, error}
      end
    end

    defp path(%URI{path: path, query: nil}), do: path

    defp path(%URI{path: path, query: query}), do: "#{path}?#{query}"

    defp receive_response(conn, request_ref, status \\ nil, body \\ []) do
      {conn, status, {body, complete}} = receive_message(conn, request_ref, status, body)

      case complete do
        :incomplete ->
          receive_response(conn, request_ref, status, body)

        :complete ->
          {:ok, conn, {status, Enum.join(body)}}
      end
    end

    defp receive_message(conn, request_ref, status, body) do
      http = HTTP

      receive do
        message ->
          {:ok, conn, responses} = http.stream(conn, message)

          {status, {body, complete}} =
            Enum.reduce(
              responses,
              {status, {body, :incomplete}},
              fn response, {status, {body, complete}} ->
                case response do
                  {:status, ^request_ref, status} ->
                    {status, {body, complete}}

                  {:data, ^request_ref, data} ->
                    {status, {body ++ [data], :incomplete}}

                  {:done, ^request_ref} ->
                    {status, {body, :complete}}

                  {_incomplete, ^request_ref, _data} ->
                    {status, {body, :incomplete}}
                end
              end
            )

          {conn, status, {body, complete}}
      end
    end

    defp scheme(%{scheme: "http"}), do: :http

    defp scheme(%{scheme: "https"}), do: :https

    defp http! do
      case Code.ensure_loaded?(HTTP) do
        true ->
          HTTP

        false ->
          raise """
          Can't find dependency for Mint. Please add :mint to your deps.

          defp deps do
            [
              {:mint, "~> 1.0"},
              {:castore, "~> 0.1"},
              ...
            ]
          end
          """
      end
    end
  end
end
