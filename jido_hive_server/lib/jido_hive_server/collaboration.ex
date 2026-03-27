defmodule JidoHiveServer.Collaboration do
  @moduledoc false

  alias JidoHiveServer.Collaboration.RoomServer
  alias JidoHiveServer.Publications
  alias JidoHiveServer.RemoteExec
  alias JidoHiveServer.Runtime

  def create_room(attrs) when is_map(attrs) do
    :ok = Runtime.ensure_instance()

    room_id = Map.get(attrs, :room_id) || Map.get(attrs, "room_id")
    brief = Map.get(attrs, :brief) || Map.get(attrs, "brief")
    rules = Map.get(attrs, :rules) || Map.get(attrs, "rules") || []

    participants =
      attrs
      |> Map.get(:participants, Map.get(attrs, "participants", []))
      |> Enum.map(&normalize_map_keys/1)

    spec =
      {RoomServer,
       room_id: room_id,
       session_id: Map.get(attrs, :session_id, "room-session-#{room_id}"),
       brief: brief,
       rules: rules,
       participants: participants}

    with {:ok, _pid} <-
           DynamicSupervisor.start_child(JidoHiveServer.Collaboration.RoomSupervisor, spec),
         {:ok, snapshot} <- fetch_room(room_id) do
      {:ok, snapshot}
    end
  end

  def fetch_room(room_id) when is_binary(room_id) do
    case Registry.lookup(JidoHiveServer.Collaboration.Registry, room_id) do
      [{pid, _value}] -> RoomServer.snapshot(pid)
      [] -> {:error, :room_not_found}
    end
  end

  def receive_result(%{"room_id" => room_id} = payload) do
    with [{pid, _value}] <- Registry.lookup(JidoHiveServer.Collaboration.Registry, room_id),
         {:ok, snapshot} <- RoomServer.apply_result(pid, payload) do
      {:ok, snapshot}
    else
      [] -> {:error, :room_not_found}
      {:error, _} = error -> error
    end
  end

  def run_first_slice(room_id) when is_binary(room_id) do
    with {:ok, snapshot} <- fetch_room(room_id),
         [architect, skeptic | _] <- snapshot.participants,
         {:ok, _} <- run_turn(room_id, snapshot, architect, 1),
         {:ok, refreshed} <- fetch_room(room_id),
         {:ok, _} <- run_turn(room_id, refreshed, skeptic, 2) do
      fetch_room(room_id)
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_room_participants}
    end
  end

  def publication_plan(room_id) when is_binary(room_id) do
    with {:ok, snapshot} <- fetch_room(room_id) do
      {:ok, Publications.build_plan(snapshot)}
    end
  end

  defp run_turn(room_id, snapshot, participant, round) do
    prompt_packet = build_prompt_packet(snapshot)
    job_id = unique_id("job")
    server = RoomServer.via(room_id)

    with {:ok, _opened} <-
           RoomServer.open_turn(server, %{
             "job_id" => job_id,
             "participant_id" => participant.participant_id,
             "round" => round,
             "prompt_packet" => prompt_packet
           }),
         :ok <-
           RemoteExec.dispatch_job(participant.target_id, %{
             "job_id" => job_id,
             "room_id" => room_id,
             "participant_id" => participant.participant_id,
             "participant_role" => participant.role,
             "capability_id" => participant.capability_id,
             "prompt_packet" => prompt_packet
           }),
         true <- wait_until(fn -> turn_completed?(room_id, job_id) end) do
      {:ok, :completed}
    else
      {:error, _} = error -> error
      false -> {:error, :turn_timeout}
    end
  end

  defp build_prompt_packet(snapshot) do
    %{
      "brief" => snapshot.brief,
      "context_summary" => context_summary(snapshot.context_entries),
      "rules" => snapshot.rules,
      "shared_instruction_log" => shared_instruction_log(snapshot.turns),
      "shared_tool_log" => shared_tool_log(snapshot.turns)
    }
  end

  defp context_summary([]), do: "No prior context."

  defp context_summary(entries) do
    entries
    |> Enum.map(fn entry -> "#{entry.entry_type}: #{entry.title}" end)
    |> Enum.join(" | ")
  end

  defp shared_instruction_log(turns) do
    Enum.map(turns, fn turn ->
      %{
        "role" => turn.participant_id,
        "body" => Map.get(turn, :result_summary, "turn queued")
      }
    end)
  end

  defp shared_tool_log(turns) do
    Enum.flat_map(turns, fn turn ->
      Enum.map(Map.get(turn, :tool_events, []), fn event ->
        %{
          "participant_id" => turn.participant_id,
          "tool_name" => event["tool_name"],
          "status" => event["status"]
        }
      end)
    end)
  end

  defp turn_completed?(room_id, job_id) do
    case fetch_room(room_id) do
      {:ok, snapshot} ->
        Enum.any?(snapshot.turns, fn turn ->
          turn.job_id == job_id and turn.status == :completed
        end)

      _ ->
        false
    end
  end

  defp wait_until(fun, attempts \\ 50)
  defp wait_until(_fun, 0), do: false

  defp wait_until(fun, attempts) do
    if fun.() do
      true
    else
      Process.sleep(100)
      wait_until(fun, attempts - 1)
    end
  end

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp normalize_map_keys(value) when is_map(value) do
    Enum.into(value, %{}, fn
      {key, nested} when is_binary(key) -> {String.to_atom(key), nested}
      {key, nested} -> {key, nested}
    end)
  end

  defp normalize_map_keys(value), do: value
end
