defmodule JidoHiveClient.ChatInput do
  @moduledoc false

  @enforce_keys [:room_id, :participant_id, :text, :submitted_at]
  defstruct [
    :room_id,
    :participant_id,
    :text,
    :submitted_at,
    participant_role: "collaborator",
    participant_kind: "human",
    authority_level: "advisory",
    local_context: %{}
  ]

  @type t :: %__MODULE__{
          room_id: String.t(),
          participant_id: String.t(),
          participant_role: String.t(),
          participant_kind: String.t(),
          authority_level: String.t(),
          text: String.t(),
          submitted_at: DateTime.t(),
          local_context: map()
        }

  @spec new(t() | map() | keyword()) :: {:ok, t()} | {:error, {:missing_field, String.t()}}
  def new(%__MODULE__{} = input), do: {:ok, input}

  def new(attrs) when is_list(attrs), do: attrs |> Enum.into(%{}) |> new()

  def new(attrs) when is_map(attrs) do
    with :ok <- require_fields(attrs, ["room_id", "participant_id", "text"]) do
      {:ok,
       %__MODULE__{
         room_id: value(attrs, "room_id"),
         participant_id: value(attrs, "participant_id"),
         participant_role: value(attrs, "participant_role") || "collaborator",
         participant_kind: value(attrs, "participant_kind") || "human",
         authority_level: value(attrs, "authority_level") || "advisory",
         text: value(attrs, "text"),
         submitted_at: datetime_value(value(attrs, "submitted_at")) || DateTime.utc_now(),
         local_context: normalize_map(value(attrs, "local_context"))
       }}
    end
  end

  def new(_other), do: {:error, {:missing_field, "room_id"}}

  defp require_fields(attrs, fields) do
    case Enum.find(fields, &missing?(attrs, &1)) do
      nil -> :ok
      field -> {:error, {:missing_field, field}}
    end
  end

  defp missing?(attrs, field) do
    case value(attrs, field) do
      value when is_binary(value) -> String.trim(value) == ""
      nil -> true
      _other -> false
    end
  end

  defp value(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || Map.get(map, existing_atom_key(key))
  end

  defp existing_atom_key(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end

  defp normalize_map(map) when is_map(map), do: map
  defp normalize_map(_other), do: %{}

  defp datetime_value(%DateTime{} = value), do: value

  defp datetime_value(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _other -> nil
    end
  end

  defp datetime_value(_other), do: nil
end
