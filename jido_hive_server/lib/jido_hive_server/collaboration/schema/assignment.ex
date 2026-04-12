defmodule JidoHiveServer.Collaboration.Schema.Assignment do
  @moduledoc false

  @type t :: %__MODULE__{
          id: String.t(),
          room_id: String.t(),
          participant_id: String.t(),
          payload: map(),
          status: String.t(),
          deadline: DateTime.t() | nil,
          inserted_at: DateTime.t(),
          meta: map()
        }

  defstruct [:id, :room_id, :participant_id, :payload, :status, :deadline, :inserted_at, :meta]

  @statuses ~w[pending active completed expired]

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    now = DateTime.utc_now()

    with {:ok, id} <- required_string(attrs, "id"),
         {:ok, room_id} <- required_string(attrs, "room_id"),
         {:ok, participant_id} <- required_string(attrs, "participant_id"),
         {:ok, status} <- status_value(attrs, "status", "pending") do
      {:ok,
       %__MODULE__{
         id: id,
         room_id: room_id,
         participant_id: participant_id,
         payload: map_value(attrs, "payload"),
         status: status,
         deadline: datetime_value(attrs, "deadline", nil),
         inserted_at: datetime_value(attrs, "inserted_at", now),
         meta: map_value(attrs, "meta")
       }}
    end
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = assignment) do
    %{
      id: assignment.id,
      room_id: assignment.room_id,
      participant_id: assignment.participant_id,
      payload: assignment.payload,
      status: assignment.status,
      deadline: assignment.deadline,
      inserted_at: assignment.inserted_at,
      meta: assignment.meta
    }
  end

  @spec terminal_status?(t() | String.t()) :: boolean()
  def terminal_status?(%__MODULE__{} = assignment), do: terminal_status?(assignment.status)
  def terminal_status?(status), do: status in ~w[completed expired]

  defp status_value(attrs, key, default) do
    status = optional_string(attrs, key) || default

    if status in @statuses do
      {:ok, status}
    else
      {:error, {:invalid_field, key}}
    end
  end

  defp required_string(attrs, key) do
    case optional_string(attrs, key) do
      nil -> {:error, {:missing_field, key}}
      value -> {:ok, value}
    end
  end

  defp optional_string(attrs, key) do
    case value(attrs, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      _other ->
        nil
    end
  end

  defp map_value(attrs, key) do
    case value(attrs, key) do
      %{} = value -> value
      _other -> %{}
    end
  end

  defp value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, existing_atom_key(key))
  end

  defp existing_atom_key(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end

  defp datetime_value(attrs, key, default) do
    case value(attrs, key) do
      %DateTime{} = value ->
        value

      value when is_binary(value) ->
        case DateTime.from_iso8601(value) do
          {:ok, datetime, _offset} -> datetime
          _other -> default
        end

      _other ->
        default
    end
  end
end
