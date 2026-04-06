defmodule JidoHiveClient.InterceptedContribution do
  @moduledoc false

  @enforce_keys [:chat_text]
  defstruct [
    :chat_text,
    summary: nil,
    contribution_type: "chat",
    authority_level: "advisory",
    context_objects: [],
    evidence_refs: [],
    contradictions: [],
    tags: [],
    raw_backend_output: nil
  ]

  @type t :: %__MODULE__{
          chat_text: String.t(),
          summary: String.t() | nil,
          contribution_type: String.t(),
          authority_level: String.t(),
          context_objects: [map()],
          evidence_refs: [map()],
          contradictions: [map()],
          tags: [String.t()],
          raw_backend_output: map() | nil
        }

  @spec new(t() | map()) :: {:ok, t()} | {:error, {:missing_field, String.t()}}
  def new(%__MODULE__{} = contribution), do: {:ok, contribution}

  def new(attrs) when is_map(attrs) do
    with :ok <- require_fields(attrs, ["chat_text"]) do
      chat_text = value(attrs, "chat_text")

      {:ok,
       %__MODULE__{
         chat_text: chat_text,
         summary: value(attrs, "summary") || chat_text,
         contribution_type: value(attrs, "contribution_type") || "chat",
         authority_level: value(attrs, "authority_level") || "advisory",
         context_objects: list_map(value(attrs, "context_objects")),
         evidence_refs: list_map(value(attrs, "evidence_refs")),
         contradictions: list_map(value(attrs, "contradictions")),
         tags: list_string(value(attrs, "tags")),
         raw_backend_output: normalize_map(value(attrs, "raw_backend_output"))
       }}
    end
  end

  def new(_other), do: {:error, {:missing_field, "chat_text"}}

  @spec new!(t() | map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, contribution} ->
        contribution

      {:error, reason} ->
        raise ArgumentError, "invalid intercepted contribution: #{inspect(reason)}"
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

  defp list_map(list) when is_list(list), do: Enum.map(list, &normalize_map/1)
  defp list_map(_other), do: []

  defp list_string(list) when is_list(list), do: Enum.filter(list, &is_binary/1)
  defp list_string(_other), do: []

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
