defmodule JidoHiveWorkerRuntime.CollaborationPrompt do
  @moduledoc false

  alias Jido.Harness.RunRequest
  alias JidoHiveWorkerRuntime.ExecutionContract

  @schema_version "jido_hive/assignment_prompt.v1"

  @spec to_run_request(map(), keyword()) :: RunRequest.t()
  def to_run_request(assignment, opts \\ []) when is_map(assignment) and is_list(opts) do
    RunRequest.new!(%{
      prompt: render_prompt(assignment),
      cwd: Keyword.get(opts, :cwd, workspace_root(assignment)),
      model: Keyword.get(opts, :model),
      timeout_ms: Keyword.get(opts, :timeout_ms),
      system_prompt: render_system_prompt(assignment),
      allowed_tools: Keyword.get(opts, :allowed_tools, []),
      metadata: %{
        "schema_version" => @schema_version,
        "room_id" => Map.get(assignment, "room_id"),
        "assignment_id" => Map.get(assignment, "assignment_id"),
        "participant_id" => Map.get(assignment, "participant_id"),
        "participant_role" => Map.get(assignment, "participant_role")
      }
    })
  end

  @spec schema_version() :: String.t()
  def schema_version, do: @schema_version

  @spec to_repair_run_request(String.t(), map(), keyword()) :: RunRequest.t()
  def to_repair_run_request(text, assignment, opts \\ [])
      when is_binary(text) and is_map(assignment) and is_list(opts) do
    RunRequest.new!(%{
      prompt: render_repair_prompt(text),
      cwd: Keyword.get(opts, :cwd, workspace_root(assignment)),
      model: Keyword.get(opts, :model),
      timeout_ms: Keyword.get(opts, :timeout_ms, 30_000),
      system_prompt: render_repair_system_prompt(assignment),
      allowed_tools: [],
      metadata: %{
        "schema_version" => @schema_version,
        "room_id" => Map.get(assignment, "room_id"),
        "assignment_id" => Map.get(assignment, "assignment_id"),
        "participant_id" => Map.get(assignment, "participant_id"),
        "participant_role" => Map.get(assignment, "participant_role"),
        "repair" => true
      }
    })
  end

  @spec render_system_prompt(map()) :: String.t()
  def render_system_prompt(assignment) when is_map(assignment) do
    allowed_contribution_types =
      contract_types(assignment, "allowed_contribution_types", ["reasoning"])

    allowed_object_types = contract_types(assignment, "allowed_object_types", ["belief", "note"])

    allowed_relation_types =
      contract_types(assignment, "allowed_relation_types", ["derives_from", "references"])

    relation_target_ids = available_relation_target_ids(assignment)
    relation_target_guidance = relation_target_guidance(relation_target_ids)

    """
    You are #{Map.get(assignment, "participant_role", "worker")} in room #{Map.get(assignment, "room_id", "unknown")}.

    Objective:
    #{Map.get(assignment, "objective", "Complete the assignment.")}

    Allowed contribution types: #{Enum.join(allowed_contribution_types, ", ")}
    Allowed object types: #{Enum.join(allowed_object_types, ", ")}
    Allowed relation types: #{Enum.join(allowed_relation_types, ", ")}
    #{relation_target_guidance}

    Return exactly one JSON object that starts with { and ends with }.
    Return the JSON object only.

    Required JSON contract:
    {
      "summary": "string",
      "contribution_type": "#{Enum.join(allowed_contribution_types, "|")}",
      "authority_level": "advisory|binding",
      "context_objects": [
        {
          "object_type": "#{Enum.join(allowed_object_types, "|")}",
          "title": "string",
          "body": "string",
          "data": {},
          "scope": {"read": ["room"], "write": ["author"]},
          "uncertainty": {"status": "provisional", "confidence": 0.0},
          "relations": [
            {
              "relation": "#{Enum.join(allowed_relation_types, "|")}",
              "target_id": "ctx-1"
            }
          ]
        }
      ],
      "artifacts": [
        {
          "artifact_type": "note|tool_output|prompt",
          "title": "string",
          "body": "string"
        }
      ]
    }

    Use [] for empty context_objects or artifacts.
    Do not return wrapper keys like schema_version, room_id, participant_id, participant_role, target_id, capability_id, assignment_id, phase, objective, status, execution, tool_events, or events.
    """
    |> String.trim()
  end

  @spec render_prompt(map()) :: String.t()
  def render_prompt(assignment) when is_map(assignment) do
    packet = %{
      "assignment_id" => Map.get(assignment, "assignment_id"),
      "room_id" => Map.get(assignment, "room_id"),
      "participant_id" => Map.get(assignment, "participant_id"),
      "participant_role" => Map.get(assignment, "participant_role"),
      "phase" => Map.get(assignment, "phase"),
      "objective" => Map.get(assignment, "objective"),
      "contribution_contract" => Map.get(assignment, "contribution_contract", %{}),
      "context_view" => Map.get(assignment, "context_view", %{})
    }

    """
    Execute the current assignment.
    Return the JSON object only.

    Assignment packet JSON:

    #{Jason.encode!(packet, pretty: true)}
    """
    |> String.trim()
  end

  defp workspace_root(assignment) do
    ExecutionContract.workspace_root(assignment)
  end

  defp render_repair_system_prompt(assignment) do
    allowed_contribution_types =
      contract_types(assignment, "allowed_contribution_types", ["reasoning"])

    allowed_object_types = contract_types(assignment, "allowed_object_types", ["belief", "note"])

    """
    Convert the provided assistant response into strict JSON only.

    Required JSON contract:
    {
      "summary": "string",
      "contribution_type": "#{Enum.join(allowed_contribution_types, "|")}",
      "authority_level": "advisory|binding",
      "context_objects": [
        {
          "object_type": "#{Enum.join(allowed_object_types, "|")}",
          "title": "string",
          "body": "string",
          "data": {},
          "scope": {"read": ["room"], "write": ["author"]},
          "uncertainty": {"status": "provisional", "confidence": 0.0},
          "relations": []
        }
      ],
      "artifacts": [
        {
          "artifact_type": "note|tool_output|prompt",
          "title": "string",
          "body": "string"
        }
      ]
    }

    Preserve meaning. Return JSON only.
    Do not return wrapper keys like schema_version, room_id, participant_id, participant_role, target_id, capability_id, assignment_id, phase, objective, status, execution, tool_events, or events.
    """
    |> String.trim()
  end

  defp render_repair_prompt(text) do
    """
    Convert this assistant response into the required JSON contract:
    - Return exactly one JSON object.
    - Do not use markdown fences.
    - Do not return wrapper keys like schema_version, room_id, participant_id, participant_role, target_id, capability_id, assignment_id, phase, objective, status, execution, tool_events, or events.

    #{text}
    """
    |> String.trim()
  end

  defp contract_types(assignment, key, default) do
    case get_in(assignment, ["contribution_contract", key]) do
      values when is_list(values) and values != [] -> values
      _other -> default
    end
  end

  defp available_relation_target_ids(assignment) do
    assignment
    |> get_in(["context_view", "context_objects"])
    |> case do
      objects when is_list(objects) ->
        objects
        |> Enum.map(&(Map.get(&1, "context_id") || Map.get(&1, :context_id)))
        |> Enum.filter(&(is_binary(&1) and String.trim(&1) != ""))
        |> Enum.uniq()

      _other ->
        []
    end
  end

  defp relation_target_guidance([]) do
    "There are no valid existing relation targets in this assignment. Use relations: [] for every context object."
  end

  defp relation_target_guidance(target_ids) do
    """
    Valid relation target ids from visible room context: #{Enum.join(target_ids, ", ")}.
    Only use target_id values from that list. Never invent ids. If none apply, use relations: [].
    """
    |> String.trim()
  end
end
