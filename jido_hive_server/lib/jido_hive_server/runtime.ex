defmodule JidoHiveServer.Runtime do
  @moduledoc false

  def instance_id do
    JidoHiveServer.RuntimeBootstrap.instance_id()
  end

  def ensure_instance do
    JidoHiveServer.RuntimeBootstrap.ensure_instance()
  end

  def context_for(actor_id, attrs \\ %{}) do
    attrs = normalize_map(attrs)

    attrs
    |> Enum.into(%{}, fn {key, value} -> {normalize_key(key), value} end)
    |> Map.put(:instance_id, instance_id())
    |> Map.put(:actor_id, actor_id)
    |> Map.put_new(:request_id, unique_id("req"))
    |> Map.put_new(:correlation_id, unique_id("corr"))
  end

  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(_), do: %{}

  defp normalize_key(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> String.to_atom(key)
  end

  defp normalize_key(key), do: key

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end
end
