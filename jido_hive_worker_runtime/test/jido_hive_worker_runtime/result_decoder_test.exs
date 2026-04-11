defmodule JidoHiveWorkerRuntime.ResultDecoderTest do
  use ExUnit.Case, async: true

  alias JidoHiveWorkerRuntime.ResultDecoder

  test "extracts fenced json and normalizes the contribution contract" do
    payload = """
    Here is the result.

    ```json
    {"summary":"ok","contribution_type":"reasoning","authority_level":"advisory","context_objects":[{"object_type":"belief","title":"A","body":"B","data":{"k":"v"},"scope":{"read":["room"],"write":["author"]},"uncertainty":{"status":"provisional","confidence":0.7},"relations":[]}],"artifacts":[]}
    ```
    """

    assert {:ok, decoded} = ResultDecoder.decode(payload)
    assert decoded["summary"] == "ok"
    assert decoded["contribution_type"] == "reasoning"

    assert [
             %{
               "object_type" => "belief",
               "title" => "A",
               "body" => "B",
               "data" => %{"k" => "v"}
             }
           ] = decoded["context_objects"]
  end

  test "defaults the summary when contribution type is present but summary is omitted" do
    payload = """
    {"contribution_type":"reasoning","context_objects":[{"object_type":"note","title":"Shared ledger","body":"Use an append-only log."}],"artifacts":[]}
    """

    assert {:ok, decoded} = ResultDecoder.decode(payload)
    assert decoded["summary"] == "reasoning contribution"
    assert decoded["authority_level"] == "advisory"
    assert [%{"object_type" => "note", "title" => "Shared ledger"}] = decoded["context_objects"]
  end

  test "extracts the first contribution object from surrounding wrapper text" do
    payload = """
    prefix text {"schema_version":"ignored","summary":"Use explicit assignments","contribution_type":"decision","authority_level":"binding","context_objects":[{"object_type":"decision","title":"Assignment transport","body":"Use assignment.start and contribution.submit","relations":[{"relation":"derives_from","target_id":"ctx-1"}]}],"artifacts":[{"artifact_type":"note","title":"operator","body":"Binding decision"}]} suffix text
    """

    assert {:ok, decoded} = ResultDecoder.decode(payload)
    assert decoded["summary"] == "Use explicit assignments"
    assert decoded["contribution_type"] == "decision"
    assert decoded["authority_level"] == "binding"

    assert [
             %{
               "object_type" => "decision",
               "title" => "Assignment transport",
               "body" => "Use assignment.start and contribution.submit",
               "relations" => [%{"relation" => "derives_from", "target_id" => "ctx-1"}]
             }
           ] = decoded["context_objects"]

    assert [%{"artifact_type" => "note", "title" => "operator"}] = decoded["artifacts"]
  end

  test "unwraps a nested contribution object with legacy object fields" do
    payload = """
    {
      "assignment_id": "asn-2",
      "room_id": "room-1",
      "participant_id": "worker-02",
      "participant_role": "worker",
      "phase": "analysis",
      "contribution": {
        "contribution_type": "reasoning",
        "authority_level": "advisory",
        "summary": "Proposes a minimal distributed collaboration protocol centered on explicit claims.",
        "objects": [
          {
            "object_id": "belief-1",
            "object_type": "belief",
            "content": "A viable protocol should define shared state and worker contribution structure."
          },
          {
            "object_id": "note-1",
            "object_type": "note",
            "content": "Require strict JSON output and stable identifiers."
          }
        ]
      }
    }
    """

    assert {:ok, decoded} = ResultDecoder.decode(payload)
    assert decoded["contribution_type"] == "reasoning"
    assert decoded["authority_level"] == "advisory"

    assert [
             %{
               "object_type" => "belief",
               "body" =>
                 "A viable protocol should define shared state and worker contribution structure."
             },
             %{
               "object_type" => "note",
               "body" => "Require strict JSON output and stable identifiers."
             }
           ] = decoded["context_objects"]
  end

  test "infers a reasoning contribution from a legacy contributions list" do
    payload = """
    {
      "assignment_id": "asn-1",
      "room_id": "room-1",
      "participant_id": "worker-01",
      "phase": "analysis",
      "contributions": [
        {
          "type": "belief",
          "object": {
            "id": "belief-1",
            "kind": "belief",
            "text": "Distributed collaboration needs explicit task allocation and shared state."
          }
        },
        {
          "type": "note",
          "object": {
            "id": "note-1",
            "kind": "note",
            "text": "Use an append-only contribution log."
          },
          "relations": [
            {
              "type": "references",
              "target_id": "belief-1"
            }
          ]
        }
      ]
    }
    """

    assert {:ok, decoded} = ResultDecoder.decode(payload)
    assert decoded["contribution_type"] == "reasoning"
    assert decoded["summary"] == "reasoning contribution"

    assert [
             %{
               "object_type" => "belief",
               "body" =>
                 "Distributed collaboration needs explicit task allocation and shared state."
             },
             %{
               "object_type" => "note",
               "body" => "Use an append-only contribution log.",
               "relations" => [%{"relation" => "references", "target_id" => "belief-1"}]
             }
           ] = decoded["context_objects"]
  end
end
