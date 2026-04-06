defmodule JidoHiveServer.Collaboration.Schema.Participant do
  @moduledoc false

  @type t :: %__MODULE__{
          participant_id: String.t(),
          participant_role: String.t(),
          participant_kind: String.t(),
          authority_level: String.t(),
          target_id: String.t() | nil,
          capability_id: String.t() | nil,
          provider: String.t() | nil,
          runtime_driver: String.t() | nil,
          workspace_root: String.t() | nil,
          metadata: map()
        }

  defstruct [
    :participant_id,
    :participant_role,
    :participant_kind,
    :authority_level,
    :target_id,
    :capability_id,
    :provider,
    :runtime_driver,
    :workspace_root,
    metadata: %{}
  ]

  @spec new(map()) :: {:ok, t()} | {:error, {:missing_field, String.t()}}
  def new(attrs) when is_map(attrs) do
    with :ok <- require_fields(attrs, ["participant_id", "participant_role"]) do
      target_id = value(attrs, "target_id")

      {:ok,
       %__MODULE__{
         participant_id: value(attrs, "participant_id"),
         participant_role: value(attrs, "participant_role"),
         participant_kind: value(attrs, "participant_kind") || default_kind(target_id),
         authority_level: value(attrs, "authority_level") || "advisory",
         target_id: target_id,
         capability_id: value(attrs, "capability_id"),
         provider: value(attrs, "provider"),
         runtime_driver: value(attrs, "runtime_driver"),
         workspace_root: value(attrs, "workspace_root"),
         metadata: normalize_map(value(attrs, "metadata") || %{})
       }}
    end
  end

  defp default_kind(target_id) when is_binary(target_id) and target_id != "", do: "runtime"
  defp default_kind(_target_id), do: "human"

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
end
