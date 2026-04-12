defmodule JidoHiveServer.Collaboration.AssignmentBuilders.Basic do
  @moduledoc false

  @behaviour JidoHiveServer.Collaboration.AssignmentBuilder

  alias JidoHiveServer.Collaboration.Schema.{Participant, RoomSnapshot}

  @impl true
  def build(%RoomSnapshot{} = snapshot, %Participant{} = participant, context)
      when is_map(context) do
    objective =
      get_in(snapshot.room.config, ["objective"]) ||
        get_in(snapshot.room.config, ["brief"]) ||
        snapshot.room.name

    payload = %{
      objective: objective,
      phase: snapshot.room.phase,
      context: %{
        room: %{
          id: snapshot.room.id,
          name: snapshot.room.name,
          status: snapshot.room.status,
          phase: snapshot.room.phase
        },
        participant: %{
          id: participant.id,
          kind: participant.kind,
          handle: participant.handle
        },
        participants:
          Enum.map(snapshot.participants, fn room_participant ->
            %{
              id: room_participant.id,
              kind: room_participant.kind,
              handle: room_participant.handle
            }
          end),
        recent_contributions:
          snapshot.contributions
          |> Enum.take(-20)
          |> Enum.map(fn contribution ->
            %{
              id: contribution.id,
              participant_id: contribution.participant_id,
              assignment_id: contribution.assignment_id,
              kind: contribution.kind,
              payload: contribution.payload
            }
          end)
      },
      prompt_config: get_in(snapshot.room.config, ["prompt_config"]) || %{},
      output_contract: get_in(snapshot.room.config, ["output_contract"]),
      executor: get_in(snapshot.room.config, ["executor"]),
      extension: get_in(snapshot.room.config, ["assignment_extension"]) || %{}
    }

    {:ok, payload}
  end
end
