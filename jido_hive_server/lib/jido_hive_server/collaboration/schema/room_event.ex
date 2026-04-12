defmodule JidoHiveServer.Collaboration.Schema.RoomEvent do
  @moduledoc false

  @type t :: %__MODULE__{
          id: String.t(),
          event_id: String.t(),
          room_id: String.t(),
          sequence: non_neg_integer() | nil,
          type: atom(),
          data: map(),
          payload: map(),
          causation_id: String.t() | nil,
          correlation_id: String.t() | nil,
          inserted_at: DateTime.t(),
          recorded_at: DateTime.t()
        }

  defstruct [
    :id,
    :event_id,
    :room_id,
    :sequence,
    :type,
    :data,
    :payload,
    :causation_id,
    :correlation_id,
    :inserted_at,
    :recorded_at
  ]

  @required_fields [:room_id, :type]

  @spec new(map()) :: {:ok, t()} | {:error, {:missing_field, atom()} | {:invalid_field, :type}}
  def new(attrs) when is_map(attrs) do
    with :ok <- validate_required(attrs),
         {:ok, type} <- event_type(attrs) do
      id = event_id(attrs)
      data = event_data(attrs)
      inserted_at = event_inserted_at(attrs)

      {:ok,
       %__MODULE__{
         id: id,
         event_id: id,
         room_id: attrs[:room_id] || attrs["room_id"],
         sequence: attrs[:sequence] || attrs["sequence"],
         type: type,
         data: data,
         payload: data,
         causation_id: attrs[:causation_id] || attrs["causation_id"],
         correlation_id: attrs[:correlation_id] || attrs["correlation_id"],
         inserted_at: inserted_at,
         recorded_at: inserted_at
       }}
    end
  end

  defp event_type(attrs), do: atom_value(attrs[:type] || attrs["type"])

  defp event_id(attrs) do
    attrs[:id] || attrs["id"] || attrs[:event_id] || attrs["event_id"]
  end

  defp event_data(attrs) do
    attrs[:data] || attrs["data"] || attrs[:payload] || attrs["payload"] || %{}
  end

  defp event_inserted_at(attrs) do
    attrs[:inserted_at] || attrs["inserted_at"] || attrs[:recorded_at] ||
      attrs["recorded_at"] || DateTime.utc_now()
  end

  defp validate_required(attrs) do
    Enum.find_value(@required_fields, :ok, fn field ->
      case attrs[field] || attrs[Atom.to_string(field)] do
        nil -> {:error, {:missing_field, field}}
        _value -> nil
      end
    end)
  end

  defp atom_value(:assignment_opened), do: {:ok, :assignment_created}
  defp atom_value(:contribution_recorded), do: {:ok, :contribution_recorded}
  defp atom_value(:assignment_abandoned), do: {:ok, :assignment_abandoned}
  defp atom_value(:contradiction_detected), do: {:ok, :contradiction_detected}
  defp atom_value(:downstream_invalidated), do: {:ok, :downstream_invalidated}
  defp atom_value(value) when is_atom(value), do: {:ok, value}
  defp atom_value("room_created"), do: {:ok, :room_created}
  defp atom_value("room_status_changed"), do: {:ok, :room_status_changed}
  defp atom_value("room_phase_changed"), do: {:ok, :room_phase_changed}
  defp atom_value("participant_joined"), do: {:ok, :participant_joined}
  defp atom_value("participant_left"), do: {:ok, :participant_left}
  defp atom_value("assignment_created"), do: {:ok, :assignment_created}
  defp atom_value("assignment_completed"), do: {:ok, :assignment_completed}
  defp atom_value("assignment_expired"), do: {:ok, :assignment_expired}
  defp atom_value("contribution_submitted"), do: {:ok, :contribution_submitted}
  defp atom_value("assignment_opened"), do: {:ok, :assignment_created}
  defp atom_value("contribution_recorded"), do: {:ok, :contribution_recorded}
  defp atom_value("assignment_abandoned"), do: {:ok, :assignment_abandoned}
  defp atom_value("contradiction_detected"), do: {:ok, :contradiction_detected}
  defp atom_value("downstream_invalidated"), do: {:ok, :downstream_invalidated}
  defp atom_value("runtime_state_changed"), do: {:ok, :room_status_changed}
  defp atom_value(_value), do: {:error, {:invalid_field, :type}}
end
