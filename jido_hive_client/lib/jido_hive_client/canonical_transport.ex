defmodule JidoHiveClient.CanonicalTransport do
  @moduledoc false

  @type room_resource :: map()
  @type assignment_resource :: map()
  @type contribution_entry :: map()
  @type room_event :: map()
  @type room_run :: map()

  @spec room_snapshot(room_resource(), [assignment_resource()], [contribution_entry()]) :: map()
  def room_snapshot(room_resource, assignments, contribution_entries)
      when is_map(room_resource) and is_list(assignments) and is_list(contribution_entries) do
    room = Map.get(room_resource, "room", %{})
    participants = Map.get(room_resource, "participants", [])
    assignment_counts = Map.get(room_resource, "assignment_counts", %{})

    contribution_count =
      Map.get(room_resource, "contribution_count", length(contribution_entries))

    contributions =
      Enum.map(contribution_entries, fn entry ->
        contribution =
          entry
          |> Map.get("contribution", %{})
          |> normalize_contribution()

        Map.put(contribution, "event_sequence", Map.get(entry, "event_sequence"))
      end)

    snapshot =
      %{
        "id" => Map.get(room, "id"),
        "name" => Map.get(room, "name"),
        "status" => Map.get(room, "status"),
        "phase" => Map.get(room, "phase"),
        "config" => Map.get(room, "config", %{}),
        "inserted_at" => Map.get(room, "inserted_at"),
        "updated_at" => Map.get(room, "updated_at"),
        "participants" => Enum.map(participants, &normalize_participant/1),
        "assignments" => Enum.map(assignments, &normalize_assignment/1),
        "contributions" => contributions,
        "assignment_counts" => assignment_counts,
        "contribution_count" => contribution_count
      }

    projected =
      snapshot
      |> JidoHiveContextGraph.project()
      |> stringify_keys()

    projected
    |> Map.put("assignment_counts", assignment_counts)
    |> Map.put("contribution_count", contribution_count)
  end

  @spec event_entries([room_event()]) :: [map()]
  def event_entries(events) when is_list(events) do
    Enum.map(events, &event_entry/1)
  end

  @spec next_cursor(term()) :: String.t() | nil
  def next_cursor(nil), do: nil
  def next_cursor(value) when is_integer(value), do: Integer.to_string(value)
  def next_cursor(value) when is_binary(value), do: value
  def next_cursor(_value), do: nil

  @spec contribution_payload(map(), String.t() | nil) :: map()
  def contribution_payload(payload, room_id \\ nil) when is_map(payload) do
    payload = stringify_keys(payload)

    %{}
    |> maybe_put("id", Map.get(payload, "id"))
    |> maybe_put("room_id", Map.get(payload, "room_id") || room_id)
    |> maybe_put("assignment_id", Map.get(payload, "assignment_id"))
    |> maybe_put("participant_id", Map.get(payload, "participant_id"))
    |> maybe_put("kind", Map.get(payload, "kind"))
    |> Map.put("payload", map_value(payload, "payload"))
    |> Map.put("meta", map_value(payload, "meta"))
  end

  @spec run_operation(room_run(), String.t() | nil) :: map()
  def run_operation(run, client_operation_id \\ nil) when is_map(run) do
    %{
      "operation_id" => Map.get(run, "id") || Map.get(run, "run_id"),
      "client_operation_id" => client_operation_id,
      "room_id" => Map.get(run, "room_id"),
      "kind" => "room_run",
      "status" => Map.get(run, "status"),
      "max_assignments" => Map.get(run, "max_assignments"),
      "assignments_started" => Map.get(run, "assignments_started"),
      "assignments_completed" => Map.get(run, "assignments_completed"),
      "assignment_timeout_ms" => Map.get(run, "assignment_timeout_ms"),
      "until" => Map.get(run, "until", %{}),
      "result" => Map.get(run, "result"),
      "error" => Map.get(run, "error"),
      "accepted_at" => Map.get(run, "inserted_at"),
      "updated_at" => Map.get(run, "updated_at")
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp event_entry(event) do
    event = stringify_keys(event)
    type = Map.get(event, "type")
    data = map_value(event, "data")
    cursor = next_cursor(Map.get(event, "sequence"))

    %{
      "entry_id" => Map.get(event, "id"),
      "event_id" => Map.get(event, "id"),
      "cursor" => cursor,
      "room_id" => Map.get(event, "room_id"),
      "sequence" => Map.get(event, "sequence"),
      "kind" => event_kind(type),
      "type" => type,
      "participant_id" => event_participant_id(type, data),
      "assignment_id" => event_assignment_id(type, data),
      "contribution_type" => event_contribution_type(type, data),
      "body" => event_body(type, data),
      "inserted_at" => Map.get(event, "inserted_at"),
      "data" => data
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp normalize_participant(participant) do
    participant = stringify_keys(participant)
    meta = map_value(participant, "meta")

    %{
      "id" => Map.get(participant, "id"),
      "room_id" => Map.get(participant, "room_id"),
      "kind" => Map.get(participant, "kind"),
      "handle" => Map.get(participant, "handle"),
      "meta" => meta,
      "joined_at" => Map.get(participant, "joined_at")
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp normalize_assignment(assignment) do
    assignment = stringify_keys(assignment)
    payload = map_value(assignment, "payload")
    meta = map_value(assignment, "meta")

    %{
      "id" => Map.get(assignment, "id"),
      "room_id" => Map.get(assignment, "room_id"),
      "participant_id" => Map.get(assignment, "participant_id"),
      "payload" => payload,
      "status" => Map.get(assignment, "status"),
      "deadline" => Map.get(assignment, "deadline"),
      "inserted_at" => Map.get(assignment, "inserted_at"),
      "meta" => meta
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp normalize_contribution(contribution) do
    contribution = stringify_keys(contribution)
    payload = map_value(contribution, "payload")
    meta = map_value(contribution, "meta")

    %{
      "id" => Map.get(contribution, "id"),
      "room_id" => Map.get(contribution, "room_id"),
      "assignment_id" => Map.get(contribution, "assignment_id"),
      "participant_id" => Map.get(contribution, "participant_id"),
      "kind" => Map.get(contribution, "kind"),
      "payload" => payload,
      "meta" => meta,
      "inserted_at" => Map.get(contribution, "inserted_at")
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp summary(payload) do
    Map.get(payload, "summary") ||
      Map.get(payload, "text") ||
      Map.get(payload, "body") ||
      Map.get(payload, "title")
  end

  defp event_kind("room_created"), do: "room.created"
  defp event_kind("room_status_changed"), do: "room.status_changed"
  defp event_kind("room_phase_changed"), do: "room.phase_changed"
  defp event_kind("participant_joined"), do: "participant.joined"
  defp event_kind("participant_left"), do: "participant.left"
  defp event_kind("assignment_created"), do: "assignment.created"
  defp event_kind("assignment_completed"), do: "assignment.completed"
  defp event_kind("assignment_expired"), do: "assignment.expired"
  defp event_kind("contribution_submitted"), do: "contribution.submitted"
  defp event_kind(type), do: type || "room.event"

  defp event_participant_id("participant_joined", data), do: get_in(data, ["participant", "id"])

  defp event_participant_id("contribution_submitted", data),
    do: get_in(data, ["contribution", "participant_id"])

  defp event_participant_id("assignment_created", data),
    do: get_in(data, ["assignment", "participant_id"])

  defp event_participant_id(_type, _data), do: nil

  defp event_assignment_id("assignment_created", data), do: get_in(data, ["assignment", "id"])
  defp event_assignment_id("assignment_completed", data), do: Map.get(data, "assignment_id")
  defp event_assignment_id("assignment_expired", data), do: Map.get(data, "assignment_id")

  defp event_assignment_id("contribution_submitted", data),
    do: get_in(data, ["contribution", "assignment_id"])

  defp event_assignment_id(_type, _data), do: nil

  defp event_contribution_type("contribution_submitted", data),
    do: get_in(data, ["contribution", "kind"])

  defp event_contribution_type(_type, _data), do: nil

  defp event_body("room_created", data), do: get_in(data, ["room", "name"])
  defp event_body("room_status_changed", data), do: Map.get(data, "status")
  defp event_body("room_phase_changed", data), do: Map.get(data, "phase")
  defp event_body("participant_joined", data), do: get_in(data, ["participant", "handle"])
  defp event_body("participant_left", data), do: Map.get(data, "participant_id")

  defp event_body("assignment_created", data),
    do: get_in(data, ["assignment", "payload", "objective"])

  defp event_body("assignment_completed", data), do: Map.get(data, "assignment_id")

  defp event_body("assignment_expired", data),
    do: Map.get(data, "reason") || Map.get(data, "assignment_id")

  defp event_body("contribution_submitted", data),
    do: data |> get_in(["contribution", "payload"]) |> summary()

  defp event_body(_type, _data), do: nil

  defp map_value(map, key) when is_map(map) do
    case Map.get(map, key) do
      %{} = value -> value
      _other -> %{}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, _key, %{} = value) when map_size(value) == 0, do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp stringify_keys(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp stringify_keys(%_{} = value), do: value |> Map.from_struct() |> stringify_keys()

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_keys(value)} end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(value), do: value
end
