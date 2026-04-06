defmodule JidoHiveClient.ResultDecoderTest do
  use ExUnit.Case, async: true

  alias JidoHiveClient.ResultDecoder

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
end
