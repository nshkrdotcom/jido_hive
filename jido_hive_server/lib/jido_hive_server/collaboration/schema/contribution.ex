defmodule JidoHiveServer.Collaboration.Schema.Contribution do
  @moduledoc false

  @schema_version "jido_hive/contribution.submit.v1"

  @type t :: %__MODULE__{
          id: String.t() | nil,
          contribution_id: String.t() | nil,
          room_id: String.t(),
          assignment_id: String.t() | nil,
          participant_id: String.t(),
          participant_role: String.t() | nil,
          participant_kind: String.t() | nil,
          target_id: String.t() | nil,
          capability_id: String.t() | nil,
          kind: String.t(),
          payload: map(),
          meta: map(),
          inserted_at: DateTime.t(),
          contribution_type: String.t(),
          authority_level: String.t(),
          summary: String.t(),
          consumed_context_ids: [String.t()],
          context_objects: [map()],
          artifacts: [map()],
          events: [map()],
          tool_events: [map()],
          approvals: [map()],
          execution: map(),
          status: String.t(),
          schema_version: String.t()
        }

  defstruct [
    :id,
    :contribution_id,
    :room_id,
    :assignment_id,
    :participant_id,
    :participant_role,
    :participant_kind,
    :target_id,
    :capability_id,
    :kind,
    payload: %{},
    meta: %{},
    inserted_at: nil,
    contribution_type: "message",
    authority_level: "advisory",
    summary: "",
    consumed_context_ids: [],
    context_objects: [],
    artifacts: [],
    events: [],
    tool_events: [],
    approvals: [],
    execution: %{},
    status: "completed",
    schema_version: @schema_version
  ]

  @spec new(map()) :: {:ok, t()} | {:error, {:missing_field, String.t()}}
  def new(attrs) when is_map(attrs) do
    with :ok <- require_fields(attrs, ["room_id", "participant_id"]) do
      contribution_id = value(attrs, "contribution_id") || value(attrs, "id")
      contribution_type = value(attrs, "contribution_type") || value(attrs, "kind") || "message"
      authority_level = value(attrs, "authority_level") || "advisory"
      summary = value(attrs, "summary") || legacy_summary(attrs)
      payload = normalize_map(value(attrs, "payload")) |> merge_legacy_payload(attrs)
      meta = normalize_map(value(attrs, "meta")) |> merge_legacy_meta(attrs)
      inserted_at = datetime_value(value(attrs, "inserted_at")) || DateTime.utc_now()

      {:ok,
       %__MODULE__{
         id: contribution_id,
         contribution_id: contribution_id,
         room_id: value(attrs, "room_id"),
         assignment_id: value(attrs, "assignment_id"),
         participant_id: value(attrs, "participant_id"),
         participant_role: value(attrs, "participant_role"),
         participant_kind: value(attrs, "participant_kind"),
         target_id: value(attrs, "target_id"),
         capability_id: value(attrs, "capability_id"),
         kind: contribution_type,
         payload: payload,
         meta: meta,
         inserted_at: inserted_at,
         contribution_type: contribution_type,
         authority_level: authority_level,
         summary: summary,
         consumed_context_ids: list_value(attrs, "consumed_context_ids"),
         context_objects: list_map(value(attrs, "context_objects")),
         artifacts: list_map(value(attrs, "artifacts")),
         events: list_map(value(attrs, "events")),
         tool_events: list_map(value(attrs, "tool_events")),
         approvals: list_map(value(attrs, "approvals")),
         execution: normalize_map(value(attrs, "execution")),
         status: value(attrs, "status") || "completed",
         schema_version: value(attrs, "schema_version") || @schema_version
       }}
    end
  end

  defp merge_legacy_payload(payload, attrs) do
    payload
    |> Map.put_new("summary", value(attrs, "summary"))
    |> Map.put_new("text", legacy_summary(attrs))
    |> Map.put_new("consumed_context_ids", list_value(attrs, "consumed_context_ids"))
    |> Map.put_new("context_objects", list_map(value(attrs, "context_objects")))
    |> Map.put_new("artifacts", list_map(value(attrs, "artifacts")))
  end

  defp merge_legacy_meta(meta, attrs) do
    meta
    |> Map.put_new("participant_role", value(attrs, "participant_role"))
    |> Map.put_new("participant_kind", value(attrs, "participant_kind"))
    |> Map.put_new("target_id", value(attrs, "target_id"))
    |> Map.put_new("capability_id", value(attrs, "capability_id"))
    |> Map.put_new("authority_level", value(attrs, "authority_level"))
    |> Map.put_new("events", list_map(value(attrs, "events")))
    |> Map.put_new("tool_events", list_map(value(attrs, "tool_events")))
    |> Map.put_new("approvals", list_map(value(attrs, "approvals")))
    |> Map.put_new("execution", normalize_map(value(attrs, "execution")))
    |> Map.put_new("status", value(attrs, "status"))
    |> Map.put_new("schema_version", value(attrs, "schema_version"))
  end

  defp legacy_summary(attrs) do
    value(attrs, "summary") || get_in(normalize_map(value(attrs, "payload")), ["text"]) || ""
  end

  defp require_fields(attrs, fields) do
    case Enum.find(fields, &missing?(attrs, &1)) do
      nil -> :ok
      field -> {:error, {:missing_field, field}}
    end
  end

  defp missing?(attrs, field) do
    case value(attrs, field) do
      value when is_binary(value) -> String.trim(value) == ""
      nil -> true
      _other -> false
    end
  end

  defp list_value(map, key) do
    case value(map, key) do
      list when is_list(list) -> Enum.filter(list, &is_binary/1)
      _other -> []
    end
  end

  defp list_map(list) when is_list(list), do: Enum.map(list, &normalize_map/1)
  defp list_map(_other), do: []

  defp value(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || Map.get(map, existing_atom_key(key))
  end

  defp existing_atom_key(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end

  defp normalize_map(map) when is_map(map), do: map
  defp normalize_map(_other), do: %{}

  defp datetime_value(%DateTime{} = value), do: value

  defp datetime_value(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _other -> nil
    end
  end

  defp datetime_value(_value), do: nil
end
