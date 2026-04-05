defmodule JidoHiveServer.Collaboration.CommandHandler do
  @moduledoc false

  alias JidoHiveServer.Collaboration.Schema.{RoomCommand, RoomEvent}

  @spec handle(RoomCommand.t()) :: {:ok, [RoomEvent.t()]} | {:error, term()}
  def handle(%RoomCommand{} = command) do
    event_type =
      case command.type do
        :create_room -> :room_created
        :open_turn -> :turn_opened
        :abandon_turn -> :turn_abandoned
        :set_runtime_state -> :runtime_state_changed
        :apply_turn_result -> result_event_type(command.payload)
      end

    with {:ok, event} <- room_event(command, event_type) do
      {:ok, [event]}
    end
  end

  defp room_event(command, type) do
    RoomEvent.new(%{
      event_id: unique_id("evt"),
      room_id: command.room_id,
      type: type,
      payload: command.payload,
      causation_id: command.command_id,
      correlation_id: command.correlation_id,
      recorded_at: command.issued_at
    })
  end

  defp result_event_type(payload) do
    case Map.get(payload, :status) || Map.get(payload, "status") do
      "failed" -> :turn_failed
      _other -> :turn_completed
    end
  end

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end
end
