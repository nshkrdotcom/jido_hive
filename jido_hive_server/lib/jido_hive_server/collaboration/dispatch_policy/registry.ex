defmodule JidoHiveServer.Collaboration.DispatchPolicy.Registry do
  @moduledoc false

  alias JidoHiveServer.Collaboration.DispatchPolicies.{HumanGate, ResourcePool, RoundRobin}

  @definitions [
    %{
      policy_id: RoundRobin.id(),
      display_name: "Round Robin",
      description: "Fixed ordered phases across the configured runtime participants.",
      module: RoundRobin
    },
    %{
      policy_id: ResourcePool.id(),
      display_name: "Resource Pool",
      description: "Uses the least-used available runtime participant for each assignment.",
      module: ResourcePool
    },
    %{
      policy_id: HumanGate.id(),
      display_name: "Human Gate",
      description:
        "Runs automatic assignments, then blocks until a binding human contribution is recorded.",
      module: HumanGate
    }
  ]

  @spec list() :: [map()]
  def list do
    Enum.map(@definitions, fn definition ->
      %{
        policy_id: definition.policy_id,
        display_name: definition.display_name,
        description: definition.description,
        config: definition.module.definition().config
      }
    end)
  end

  @spec fetch(String.t()) :: {:ok, map()} | {:error, :unknown_policy}
  def fetch(policy_id) when is_binary(policy_id) do
    Enum.find_value(@definitions, {:error, :unknown_policy}, fn definition ->
      if definition.policy_id == policy_id do
        {:ok,
         %{
           policy_id: definition.policy_id,
           display_name: definition.display_name,
           description: definition.description,
           config: definition.module.definition().config
         }}
      end
    end)
  end

  @spec fetch_module(String.t()) :: {:ok, module()} | {:error, :unknown_policy}
  def fetch_module(policy_id) when is_binary(policy_id) do
    case Enum.find(@definitions, &(&1.policy_id == policy_id)) do
      %{module: module} -> {:ok, module}
      nil -> {:error, :unknown_policy}
    end
  end
end
