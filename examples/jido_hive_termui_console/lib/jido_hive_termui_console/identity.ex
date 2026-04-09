defmodule JidoHiveTermuiConsole.Identity do
  @moduledoc false

  alias JidoHiveClient.Operator

  defstruct participant_id: nil,
            participant_role: "coordinator",
            authority_level: "binding",
            display_name: nil

  @type t :: %__MODULE__{}

  @spec load(keyword()) :: t()
  def load(opts \\ []) do
    operator_module = Keyword.get(opts, :operator_module, Operator)
    config = operator_module.load_config()
    participant_id = keyword_or_config(opts, :participant_id, config) || default_participant_id()
    participant_role = keyword_or_config(opts, :participant_role, config) || "coordinator"
    authority_level = keyword_or_config(opts, :authority_level, config) || "binding"

    %__MODULE__{
      participant_id: participant_id,
      participant_role: participant_role,
      authority_level: authority_level,
      display_name: participant_id
    }
  end

  @spec to_embedded_opts(t()) :: keyword()
  def to_embedded_opts(%__MODULE__{} = identity) do
    [
      participant_id: identity.participant_id,
      participant_role: identity.participant_role,
      participant_kind: "human"
    ]
  end

  @spec to_submit_attrs(t(), map()) :: map()
  def to_submit_attrs(%__MODULE__{} = identity, base_attrs) when is_map(base_attrs) do
    Map.merge(base_attrs, %{
      authority_level: identity.authority_level,
      participant_id: identity.participant_id,
      participant_role: identity.participant_role
    })
  end

  @spec to_contribution_base(t(), String.t()) :: map()
  def to_contribution_base(%__MODULE__{} = identity, room_id) when is_binary(room_id) do
    %{
      "room_id" => room_id,
      "participant_id" => identity.participant_id,
      "participant_role" => identity.participant_role,
      "participant_kind" => "human",
      "authority_level" => identity.authority_level,
      "execution" => %{"status" => "completed"},
      "status" => "completed"
    }
  end

  defp default_participant_id do
    {:ok, hostname} = :inet.gethostname()

    "human-#{List.to_string(hostname)}"
  end

  defp keyword_or_config(opts, key, config) do
    Keyword.get(opts, key, Map.get(config, Atom.to_string(key)))
  end
end
