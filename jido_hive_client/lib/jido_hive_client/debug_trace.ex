defmodule JidoHiveClient.DebugTrace do
  @moduledoc false

  @spec emit(:debug | :info | :warning | :error, String.t(), map()) :: :ok
  def emit(level, event, metadata \\ %{})
      when level in [:debug, :info, :warning, :error] and is_binary(event) and is_map(metadata) do
    case Application.get_env(:jido_hive_client, :debug_trace_level) do
      configured_level when configured_level in [:debug, :info] ->
        if should_emit?(level, configured_level) do
          payload = %{
            "ts" =>
              DateTime.utc_now() |> DateTime.truncate(:millisecond) |> DateTime.to_iso8601(),
            "app" => "jido_hive_client",
            "level" => Atom.to_string(level),
            "event" => event,
            "metadata" => normalize(metadata)
          }

          IO.binwrite(:stderr, Jason.encode!(payload) <> "\n")
        end

        :ok

      _other ->
        :ok
    end
  end

  defp should_emit?(level, :debug), do: severity(level) >= severity(:debug)
  defp should_emit?(level, :info), do: severity(level) >= severity(:info)

  defp severity(:debug), do: 10
  defp severity(:info), do: 20
  defp severity(:warning), do: 30
  defp severity(:error), do: 40

  defp normalize(value) when is_map(value) do
    Map.new(value, fn {key, nested} -> {to_string(key), normalize(nested)} end)
  end

  defp normalize(value) when is_list(value), do: Enum.map(value, &normalize/1)
  defp normalize(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize(value), do: value
end
