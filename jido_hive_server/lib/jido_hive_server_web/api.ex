defmodule JidoHiveServerWeb.API do
  @moduledoc false

  @schema_version "jido_hive/http.v1"

  def schema_version, do: @schema_version

  def data(payload, meta \\ %{}) do
    %{
      data: normalize(payload),
      meta: Map.put_new(normalize(meta), "schema_version", @schema_version)
    }
  end

  def error(code, message, details \\ %{}) do
    %{
      error: %{
        code: code,
        message: message,
        details: normalize(details)
      }
    }
  end

  def normalize(%DateTime{} = value), do: DateTime.to_iso8601(value)
  def normalize(%_{} = value), do: value |> Map.from_struct() |> normalize()

  def normalize(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), normalize(value)} end)

  def normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)
  def normalize(value), do: value
end
