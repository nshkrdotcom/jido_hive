defmodule JidoHiveServer.Collaboration.AssignmentBuilder do
  @moduledoc false

  alias JidoHiveServer.Collaboration.Schema.{Participant, RoomSnapshot}

  @callback build(
              snapshot :: RoomSnapshot.t(),
              participant :: Participant.t(),
              context :: %{
                policy_state: map(),
                availability: %{String.t() => map()},
                now: DateTime.t()
              }
            ) :: {:ok, map()} | {:error, term()}
end
