defmodule JidoHiveServer.Collaboration.Schema.RoomCommand do
  @moduledoc false

  @type t :: %__MODULE__{
          command_id: String.t(),
          room_id: String.t(),
          type: atom(),
          payload: map(),
          causation_id: String.t() | nil,
          correlation_id: String.t() | nil,
          issued_at: DateTime.t()
        }

  defstruct [
    :command_id,
    :room_id,
    :type,
    :payload,
    :causation_id,
    :correlation_id,
    :issued_at
  ]

  @required_fields [:command_id, :room_id, :type, :payload, :issued_at]

  @spec new(map()) :: {:ok, t()} | {:error, {:missing_field, atom()}}
  def new(attrs) when is_map(attrs) do
    with :ok <- validate_required(attrs) do
      {:ok,
       %__MODULE__{
         command_id: attrs[:command_id] || attrs["command_id"],
         room_id: attrs[:room_id] || attrs["room_id"],
         type: attrs[:type] || attrs["type"],
         payload: attrs[:payload] || attrs["payload"],
         causation_id: attrs[:causation_id] || attrs["causation_id"],
         correlation_id: attrs[:correlation_id] || attrs["correlation_id"],
         issued_at: attrs[:issued_at] || attrs["issued_at"]
       }}
    end
  end

  defp validate_required(attrs) do
    Enum.find_value(@required_fields, :ok, fn field ->
      case attrs[field] || attrs[Atom.to_string(field)] do
        nil -> {:error, {:missing_field, field}}
        _value -> nil
      end
    end)
  end
end
