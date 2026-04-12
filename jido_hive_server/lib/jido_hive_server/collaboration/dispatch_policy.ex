defmodule JidoHiveServer.Collaboration.DispatchPolicy do
  @moduledoc false

  alias JidoHiveServer.Collaboration.Schema.{RoomEvent, RoomSnapshot}

  @type room_patch :: %{
          optional(:phase) => String.t() | nil,
          optional(:status) => String.t()
        }

  @callback id() :: String.t()
  @callback definition() :: map()

  @callback init(snapshot :: RoomSnapshot.t(), context :: map()) ::
              {:ok, policy_state :: map(), room_patch()}

  @callback handle_event(
              event :: RoomEvent.t(),
              snapshot :: RoomSnapshot.t(),
              policy_state :: map(),
              context :: map()
            ) :: {:ok, policy_state :: map(), room_patch()}

  @callback select(
              snapshot :: RoomSnapshot.t(),
              context :: %{
                availability: %{String.t() => map()},
                policy_state: map(),
                now: DateTime.t()
              }
            ) ::
              {:dispatch, [participant_id :: String.t()], policy_state :: map(), room_patch()}
              | {:wait, reason :: term(), policy_state :: map(), room_patch()}
              | {:complete, completion :: %{reason: term()}, policy_state :: map(), room_patch()}
              | {:close, reason :: term(), policy_state :: map(), room_patch()}
end
