defmodule JidoHiveServer.Collaboration.Schema.Room do
  @moduledoc false

  @statuses ~w[waiting active completed closed failed]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          status: String.t(),
          phase: String.t() | nil,
          config: map(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct [:id, :name, :status, :phase, :config, :inserted_at, :updated_at]

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    now = DateTime.utc_now()

    with {:ok, id} <- required_string(attrs, "id"),
         {:ok, name} <- required_string(attrs, "name"),
         {:ok, status} <- status_value(attrs, "status", "waiting") do
      {:ok,
       %__MODULE__{
         id: id,
         name: name,
         status: status,
         phase: optional_string(attrs, "phase"),
         config: map_value(attrs, "config"),
         inserted_at: datetime_value(attrs, "inserted_at", now),
         updated_at: datetime_value(attrs, "updated_at", now)
       }}
    end
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = room) do
    %{
      id: room.id,
      name: room.name,
      status: room.status,
      phase: room.phase,
      config: room.config,
      inserted_at: room.inserted_at,
      updated_at: room.updated_at
    }
  end

  @spec valid_status?(term()) :: boolean()
  def valid_status?(status), do: status in @statuses

  defp status_value(attrs, key, default) do
    status = optional_string(attrs, key) || default

    if valid_status?(status) do
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

  defp value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, existing_atom_key(key))
  end

  defp existing_atom_key(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end
end
