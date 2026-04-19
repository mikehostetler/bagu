defmodule TimeZoneInfo.Downloader do
  @moduledoc """
  The behaviour for downloaders.
  """

  @typedoc """
  The `mode` to download the data.

  Possible modes:
  - `:iana` downloads the data as a zipped tar archive in IANA format.
  - `:etf` downloads the data as a compressed file in the `TimeZoneInfo`
    [External Term Format](http://erlang.org/doc/apps/erts/erl_ext_dist.html).
  - `:ws` downloads the data from a web service.  In this mode, the
    configuration is sent to the server. The returned data is transformed
    according to the config on the server and comes in the same format as in the
    mode `:etf`.
  """
  @type mode :: :iana | :etf | :ws

  @typedoc "HTTP headers."
  @type headers() :: [{header_name :: String.t(), header_value :: String.t()}]

  @type opts :: [
          headers: headers(),
          mode: mode()
        ]

  @typedoc "HTTP status code"
  @type status_code :: non_neg_integer()

  @type download :: {:ok, mode(), {status_code(), binary()}}

  @mode [:iana, :etf, :ws]

  @callback download(uri :: URI.t(), opts :: opts) :: download() | {:error, term()}

  @doc false
  @spec download(keyword()) :: download() | {:error, term()}
  def download(config) do
    with {:ok, mode} <- mode(),
         {:ok, uri} <- uri(mode, config),
         {:ok, opts} <- opts(config),
         {:ok, impl} <- impl(),
         {:ok, data} <- impl.download(uri, opts),
         do: {:ok, mode, data}
  end

  defp impl do
    module =
      :time_zone_info
      |> Application.get_env(:downloader)
      |> Keyword.fetch!(:module)

    if Code.ensure_loaded?(module) do
      {:ok, module}
    else
      if module do
        {:error, downloader_unavailable: module}
      else
        {:error, :no_downloader_implementation}
      end
    end
  end

  defp mode do
    with {:ok, value} <- fetch_env(:mode) do
      case value in @mode do
        true -> {:ok, value}
        false -> {:error, {:invalid_config, [downloader: [mode: value]]}}
      end
    end
  end

  defp uri do
    with {:ok, uri} <- fetch_env(:uri) do
      {:ok, URI.parse(uri)}
    end
  end

  defp uri(:ws, config) do
    with {:ok, %URI{} = uri} <- uri() do
      query = config |> prepare_query() |> URI.encode_query()
      {:ok, %{uri | query: query}}
    end
  end

  defp uri(_mode, _config), do: uri()

  defp prepare_query(config) do
    config
    |> prepare_query(:time_zones, :"time_zones[]")
    |> prepare_query(:files, :"files[]")
  end

  defp prepare_query(config, key, query_key) do
    case Keyword.pop(config, key) do
      {[_ | _] = values, config} ->
        values |> Enum.map(fn value -> {query_key, value} end) |> Keyword.merge(config)

      {_, config} ->
        config
    end
  end

  defp opts(config) do
    with {:ok, opts} <- fetch_env() do
      opts =
        opts
        |> Keyword.delete(:module)
        |> Keyword.delete(:uri)
        |> add_header("if-none-match", config[:checksum])

      {:ok, opts}
    end
  end

  defp add_header(opts, _key, nil), do: opts

  defp add_header(opts, key, value) do
    case opts[:headers] do
      nil ->
        Keyword.put(opts, :headers, [{key, value}])

      headers ->
        Keyword.put(opts, :headers, [{key, value} | headers])
    end
  end

  defp fetch_env do
    with :error <- Application.fetch_env(:time_zone_info, :downloader) do
      {:error, {:invalid_config, :downloader}}
    end
  end

  defp fetch_env(key) do
    with {:ok, env} <- fetch_env(),
         :error <- Keyword.fetch(env, key) do
      {:error, {:invalid_config, [:downloader, key]}}
    end
  end
end
