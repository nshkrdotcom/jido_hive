defmodule JidoHiveClient.CollaborationPrompt do
  @moduledoc false

  alias Jido.Harness.RunRequest
  alias JidoHiveClient.ExecutionContract

  @schema_version "jido_hive/collab_envelope.v1"

  @spec to_run_request(map(), keyword()) :: RunRequest.t()
  def to_run_request(job, opts \\ []) when is_map(job) and is_list(opts) do
    envelope = Map.fetch!(job, "collaboration_envelope")

    RunRequest.new!(%{
      prompt: render_prompt(envelope),
      cwd: Keyword.get(opts, :cwd, workspace_root(job)),
      model: Keyword.get(opts, :model),
      timeout_ms: Keyword.get(opts, :timeout_ms),
      system_prompt: render_system_prompt(envelope),
      allowed_tools: Keyword.get(opts, :allowed_tools, []),
      metadata: %{
        "schema_version" => @schema_version,
        "room_id" => Map.get(job, "room_id"),
        "job_id" => Map.get(job, "job_id"),
        "participant_id" => Map.get(job, "participant_id"),
        "participant_role" => Map.get(job, "participant_role")
      }
    })
  end

  @spec schema_version() :: String.t()
  def schema_version, do: @schema_version

  @spec to_repair_run_request(String.t(), map(), keyword()) :: RunRequest.t()
  def to_repair_run_request(text, job, opts \\ [])
      when is_binary(text) and is_map(job) and is_list(opts) do
    RunRequest.new!(%{
      prompt: render_repair_prompt(text),
      cwd: Keyword.get(opts, :cwd, workspace_root(job)),
      model: Keyword.get(opts, :model),
      timeout_ms: Keyword.get(opts, :timeout_ms, 30_000),
      system_prompt: render_repair_system_prompt(job),
      allowed_tools: [],
      metadata: %{
        "schema_version" => @schema_version,
        "room_id" => Map.get(job, "room_id"),
        "job_id" => Map.get(job, "job_id"),
        "participant_id" => Map.get(job, "participant_id"),
        "participant_role" => Map.get(job, "participant_role"),
        "repair" => true
      }
    })
  end

  @spec render_system_prompt(map()) :: String.t()
  def render_system_prompt(envelope) when is_map(envelope) do
    """
    #{render_contract_instructions(envelope)}
    """
    |> String.trim()
  end

  @spec render_prompt(map()) :: String.t()
  def render_prompt(envelope) when is_map(envelope) do
    """
    Execute the current collaboration turn using this shared envelope.
    Return the JSON object only.

    #{render_contract_instructions(envelope)}

    Shared envelope JSON:

    #{Jason.encode!(envelope, pretty: true)}
    """
    |> String.trim()
  end

  defp workspace_root(job) do
    ExecutionContract.workspace_root(job)
  end

  defp render_repair_system_prompt(job) do
    allowed_ops = allowed_ops(job)

    """
    Convert the provided assistant response into strict JSON only.

    Required contract:
    {
      "summary": "string",
      "actions": [
        {
          "op": "#{allowed_ops}",
          "title": "string",
          "body": "string",
          "severity": "low|medium|high|null",
          "targets": [
            {
              "entry_ref": "string|null",
              "dispute_id": "string|null"
            }
          ]
        }
      ],
      "artifacts": [
        {
          "artifact_type": "prompt|tool_output|note",
          "title": "string",
          "body": "string"
        }
      ]
    }

    Preserve meaning. If the source mentions dispute IDs or entry refs inline,
    move them into targets. Do not use tools. Return JSON only.
    Do not return wrapper keys like schema_version, room_id, participant_id,
    phase, ops, or ids outside the allowed actions/artifacts structure.
    """
    |> String.trim()
  end

  defp render_repair_prompt(text) do
    """
    Convert this assistant response into the required JSON contract:
    - Return exactly one JSON object.
    - Do not use markdown fences.
    - Do not return wrapper keys like schema_version, room_id, participant_id,
      phase, or ops.

    #{text}
    """
    |> String.trim()
  end

  defp render_contract_instructions(envelope) do
    turn = Map.fetch!(envelope, "turn")
    referee = Map.fetch!(envelope, "referee")
    room = Map.fetch!(envelope, "room")
    allowed_ops = allowed_ops_from_envelope(envelope)

    """
    You are #{turn["participant_role"]} in Jido Hive room #{room["room_id"]}.

    Follow the referee objective exactly:
    #{turn["objective"]}

    Follow these referee directives:
    #{Enum.map_join(referee["directives"] || [], "\n", &"* #{&1}")}

    Return only JSON matching this contract:
    {
      "summary": "string",
      "actions": [
        {
          "op": "CLAIM|EVIDENCE|OBJECT|REVISE|DECIDE|PUBLISH",
          "title": "string",
          "body": "string",
          "severity": "low|medium|high|null",
          "targets": [
            {
              "entry_ref": "claim:1|evidence:2|publish_request:3|null",
              "dispute_id": "dispute:1|null"
            }
          ]
        }
      ],
      "artifacts": [
        {
          "artifact_type": "prompt|tool_output|note",
          "title": "string",
          "body": "string"
        }
      ]
    }

    Allowed action ops for this turn: #{allowed_ops}

    Return exactly one JSON object that starts with { and ends with }.
    Use [] for empty actions or artifacts.
    Do not inspect local files, run shell commands, or call tools unless tools
    were explicitly enabled for this turn and the shared envelope is
    insufficient.
    Do not add markdown fences, prose, or commentary outside that JSON object.
    Do not return wrapper keys like schema_version, room_id, participant_id,
    phase, ops, or ids outside action/artifact objects.
    """
    |> String.trim()
  end

  defp allowed_ops(job) do
    job
    |> get_in(["collaboration_envelope", "turn", "response_contract", "allowed_ops"])
    |> case do
      ops when is_list(ops) -> Enum.join(ops, "|")
      _other -> "CLAIM|EVIDENCE|OBJECT|REVISE|DECIDE|PUBLISH"
    end
  end

  defp allowed_ops_from_envelope(envelope) do
    envelope
    |> get_in(["turn", "response_contract", "allowed_ops"])
    |> case do
      ops when is_list(ops) -> Enum.join(ops, ", ")
      _other -> "CLAIM, EVIDENCE, OBJECT, REVISE, DECIDE, PUBLISH"
    end
  end
end
