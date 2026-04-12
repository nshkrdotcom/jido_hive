defmodule JidoHiveServer.Collaboration.Schema.RoomSnapshot do
  @moduledoc false

  alias JidoHiveServer.Collaboration.Schema.{Assignment, Contribution, Participant, Room}

  @version "jido_hive/room_snapshot.v1"
  @required_top_level_keys ~w[room participants assignments contributions dispatch clocks replay]

  @type dispatch_state :: %{
          policy_id: String.t(),
          policy_state: map(),
          active_assignment_ids: [String.t()],
          completed_assignment_ids: [String.t()]
        }

  @type clocks :: %{
          next_assignment_seq: pos_integer(),
          next_contribution_seq: pos_integer(),
          next_event_sequence: pos_integer()
        }

  @type replay :: %{
          checkpoint_event_sequence: non_neg_integer()
        }

  @type t :: %__MODULE__{
          version: String.t(),
          room: Room.t(),
          participants: [Participant.t()],
          assignments: [Assignment.t()],
          contributions: [Contribution.t()],
          dispatch: dispatch_state(),
          clocks: clocks(),
          replay: replay()
        }

  defstruct [
    :version,
    :room,
    :participants,
    :assignments,
    :contributions,
    :dispatch,
    :clocks,
    :replay
  ]

  @spec version() :: String.t()
  def version, do: @version

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    with :ok <- validate_version(attrs),
         {:ok, room} <- build_room(attrs),
         {:ok, participants} <- build_list(attrs, "participants", &Participant.new/1),
         {:ok, assignments} <- build_list(attrs, "assignments", &Assignment.new/1),
         {:ok, contributions} <- build_list(attrs, "contributions", &Contribution.new/1),
         {:ok, dispatch} <- build_dispatch(attrs),
         {:ok, clocks} <- build_clocks(attrs),
         {:ok, replay} <- build_replay(attrs) do
      {:ok,
       %__MODULE__{
         version: @version,
         room: room,
         participants: participants,
         assignments: assignments,
         contributions: contributions,
         dispatch: dispatch,
         clocks: clocks,
         replay: replay
       }}
    end
  end

  @spec initial(Room.t(), String.t(), map()) :: t()
  def initial(%Room{} = room, policy_id, policy_state)
      when is_binary(policy_id) and is_map(policy_state) do
    %__MODULE__{
      version: @version,
      room: room,
      participants: [],
      assignments: [],
      contributions: [],
      dispatch: %{
        policy_id: policy_id,
        policy_state: policy_state,
        active_assignment_ids: [],
        completed_assignment_ids: []
      },
      clocks: %{
        next_assignment_seq: 1,
        next_contribution_seq: 1,
        next_event_sequence: 1
      },
      replay: %{
        checkpoint_event_sequence: 0
      }
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = snapshot) do
    %{
      version: snapshot.version,
      room: Room.to_map(snapshot.room),
      participants: Enum.map(snapshot.participants, &Participant.to_map/1),
      assignments: Enum.map(snapshot.assignments, &Assignment.to_map/1),
      contributions: Enum.map(snapshot.contributions, &Contribution.to_map/1),
      dispatch: snapshot.dispatch,
      clocks: snapshot.clocks,
      replay: snapshot.replay
    }
  end

  @spec valid_snapshot_map?(map()) :: boolean()
  def valid_snapshot_map?(snapshot) when is_map(snapshot) do
    version(snapshot) == @version and
      required_top_level_keys?(snapshot) and
      valid_collection_fields?(snapshot) and
      valid_map_fields?(snapshot) and
      valid_checkpoint_sequence?(snapshot)
  end

  def valid_snapshot_map?(_snapshot), do: false

  defp required_top_level_keys?(snapshot) do
    Enum.all?(@required_top_level_keys, &(not is_nil(value(snapshot, &1))))
  end

  defp valid_collection_fields?(snapshot) do
    is_list(value(snapshot, "participants")) and
      is_list(value(snapshot, "assignments")) and
      is_list(value(snapshot, "contributions"))
  end

  defp valid_map_fields?(snapshot) do
    match?(%{} = _room, value(snapshot, "room")) and
      is_map(value(snapshot, "dispatch")) and
      is_map(value(snapshot, "clocks")) and
      is_map(value(snapshot, "replay"))
  end

  defp valid_checkpoint_sequence?(snapshot) do
    is_integer(value(map_value(snapshot, "replay"), "checkpoint_event_sequence"))
  end

  defp validate_version(attrs) do
    if version(attrs) == @version do
      :ok
    else
      {:error, :invalid_snapshot_version}
    end
  end

  defp build_room(attrs) do
    attrs
    |> map_value("room")
    |> Room.new()
  end

  defp build_list(attrs, key, builder) do
    attrs
    |> list_value(key)
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case builder.(item) do
        {:ok, built} -> {:cont, {:ok, acc ++ [built]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp build_dispatch(attrs) do
    dispatch = map_value(attrs, "dispatch")

    with {:ok, policy_id} <- required_string(dispatch, "policy_id") do
      {:ok,
       %{
         policy_id: policy_id,
         policy_state: map_value(dispatch, "policy_state"),
         active_assignment_ids: string_list(dispatch, "active_assignment_ids"),
         completed_assignment_ids: string_list(dispatch, "completed_assignment_ids")
       }}
    end
  end

  defp build_clocks(attrs) do
    clocks = map_value(attrs, "clocks")

    {:ok,
     %{
       next_assignment_seq: positive_integer(clocks, "next_assignment_seq", 1),
       next_contribution_seq: positive_integer(clocks, "next_contribution_seq", 1),
       next_event_sequence: positive_integer(clocks, "next_event_sequence", 1)
     }}
  end

  defp build_replay(attrs) do
    replay = map_value(attrs, "replay")
    checkpoint = non_neg_integer(replay, "checkpoint_event_sequence", 0)
    {:ok, %{checkpoint_event_sequence: checkpoint}}
  end

  defp version(attrs), do: optional_string(attrs, "version")

  defp positive_integer(attrs, key, default) do
    case integer_value(attrs, key) do
      value when is_integer(value) and value > 0 -> value
      _other -> default
    end
  end

  defp non_neg_integer(attrs, key, default) do
    case integer_value(attrs, key) do
      value when is_integer(value) and value >= 0 -> value
      _other -> default
    end
  end

  defp integer_value(attrs, key) do
    case value(attrs, key) do
      value when is_integer(value) ->
        value

      value when is_binary(value) ->
        case Integer.parse(value) do
          {integer, ""} -> integer
          _other -> nil
        end

      _other ->
        nil
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

  defp string_list(attrs, key) do
    attrs
    |> list_value(key)
    |> Enum.filter(&is_binary/1)
  end

  defp list_value(attrs, key) do
    case value(attrs, key) do
      values when is_list(values) -> values
      _other -> []
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
end
