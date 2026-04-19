defmodule TimeZoneInfo.FileArchive do
  @moduledoc false

  # This module provides a function to extract files form a zipped tar archive.

  @doc """
  Extracts the given `files` from the `archive`.
  """
  @spec extract(binary(), [Path.t()]) ::
          {:ok, %{optional(String.t()) => binary()}} | {:error, term()}
  def extract(archive, files) do
    opts = [:memory, :compressed, files(files)]

    with {:ok, extracted} <- :erl_tar.extract({:binary, archive}, opts) do
      to_map(extracted, files)
    end
  end

  defp files(files), do: {:files, Enum.map(files, &String.to_charlist/1)}

  defp to_map(extracted, files) do
    result =
      Enum.reduce(extracted, {%{}, files}, fn {name, content}, {map, list} ->
        name = List.to_string(name)
        {Map.put(map, name, content), List.delete(list, name)}
      end)

    case result do
      {files, []} -> {:ok, files}
      {_files, not_found} -> {:error, {:not_found, not_found}}
    end
  end
end
