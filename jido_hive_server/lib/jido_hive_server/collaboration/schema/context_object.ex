defmodule JidoHiveServer.Collaboration.Schema.ContextObject do
  @moduledoc false

  @type t :: %__MODULE__{
          context_id: String.t(),
          object_type: String.t(),
          title: String.t() | nil,
          body: String.t() | nil,
          data: map(),
          authored_by: map(),
          provenance: map(),
          scope: map(),
          uncertainty: map(),
          relations: [map()],
          inserted_at: DateTime.t()
        }

  defstruct [
    :context_id,
    :object_type,
    :title,
    :body,
    data: %{},
    authored_by: %{},
    provenance: %{},
    scope: %{read: ["room"], write: ["author"]},
    uncertainty: %{status: "provisional", confidence: nil, rationale: nil},
    relations: [],
    inserted_at: nil
  ]

  @spec from_draft(map(), map()) :: {:ok, t()} | {:error, {:missing_field, String.t()}}
  def from_draft(draft, attrs) when is_map(draft) and is_map(attrs) do
    with :ok <- require_fields(draft, ["object_type"]),
         :ok <- require_fields(attrs, ["context_id"]) do
      {:ok,
       %__MODULE__{
         context_id: value(attrs, "context_id"),
         object_type: value(draft, "object_type"),
         title: value(draft, "title"),
         body: value(draft, "body"),
         data: normalize_map(value(draft, "data")),
         authored_by: normalize_map(value(attrs, "authored_by")),
         provenance: normalize_map(value(attrs, "provenance")),
         scope: normalize_scope(value(draft, "scope")),
         uncertainty: normalize_uncertainty(value(draft, "uncertainty")),
         relations: normalize_relations(value(draft, "relations")),
         inserted_at: datetime_value(value(attrs, "inserted_at")) || DateTime.utc_now()
       }}
    end
  end

  defp normalize_scope(%{} = scope) do
    %{
      read: list_value(scope, "read", ["room"]),
      write: list_value(scope, "write", ["author"])
    }
  end

  defp normalize_scope(_other), do: %{read: ["room"], write: ["author"]}

  defp normalize_uncertainty(%{} = uncertainty) do
    %{
      status: value(uncertainty, "status") || "provisional",
      confidence: numeric_value(value(uncertainty, "confidence")),
      rationale: value(uncertainty, "rationale")
    }
  end

  defp normalize_uncertainty(_other),
    do: %{status: "provisional", confidence: nil, rationale: nil}

  defp normalize_relations(relations) when is_list(relations) do
    Enum.map(relations, fn relation ->
      %{
        relation: value(relation, "relation"),
        target_id: value(relation, "target_id")
      }
    end)
  end

  defp normalize_relations(_other), do: []

  defp list_value(map, key, default) do
    case value(map, key) do
      list when is_list(list) -> Enum.filter(list, &is_binary/1)
      _other -> default
    end
  end

  defp numeric_value(value) when is_float(value), do: value
  defp numeric_value(value) when is_integer(value), do: value / 1
  defp numeric_value(_value), do: nil

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
