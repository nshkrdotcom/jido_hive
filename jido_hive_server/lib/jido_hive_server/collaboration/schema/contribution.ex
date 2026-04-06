defmodule JidoHiveServer.Collaboration.Schema.Contribution do
  @moduledoc false

  @schema_version "jido_hive/contribution.submit.v1"

  @type t :: %__MODULE__{
          contribution_id: String.t() | nil,
          room_id: String.t(),
          assignment_id: String.t() | nil,
          participant_id: String.t(),
          participant_role: String.t(),
          target_id: String.t() | nil,
          capability_id: String.t() | nil,
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
    :contribution_id,
    :room_id,
    :assignment_id,
    :participant_id,
    :participant_role,
    :target_id,
    :capability_id,
    :contribution_type,
    :authority_level,
    :summary,
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
    with :ok <-
           require_fields(attrs, [
             "room_id",
             "participant_id",
             "participant_role",
             "contribution_type",
             "authority_level",
             "summary"
           ]) do
      {:ok,
       %__MODULE__{
         contribution_id: value(attrs, "contribution_id"),
         room_id: value(attrs, "room_id"),
         assignment_id: value(attrs, "assignment_id"),
         participant_id: value(attrs, "participant_id"),
         participant_role: value(attrs, "participant_role"),
         target_id: value(attrs, "target_id"),
         capability_id: value(attrs, "capability_id"),
         contribution_type: value(attrs, "contribution_type"),
         authority_level: value(attrs, "authority_level"),
         summary: value(attrs, "summary"),
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
end
