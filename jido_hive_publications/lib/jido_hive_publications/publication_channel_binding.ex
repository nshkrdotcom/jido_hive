defmodule JidoHivePublications.PublicationChannelBinding do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:channel, :string)
    field(:field, :string)
    field(:description, :string)
    field(:source, :string)
  end

  @type t :: %__MODULE__{
          channel: String.t() | nil,
          field: String.t() | nil,
          description: String.t() | nil,
          source: String.t() | nil
        }

  @spec new!(String.t(), map()) :: __MODULE__.t()
  def new!(channel, attrs) when is_binary(channel) and is_map(attrs) do
    %__MODULE__{}
    |> changeset(Map.put(attrs, :channel, channel))
    |> apply_action!(:insert)
  end

  @spec to_map(__MODULE__.t()) :: map()
  def to_map(%__MODULE__{} = binding) do
    %{
      channel: binding.channel,
      field: binding.field,
      description: binding.description,
      source: binding.source
    }
  end

  defp changeset(binding, attrs) do
    binding
    |> cast(attrs, [:channel, :field, :description, :source])
    |> validate_required([:channel, :field])
  end
end
