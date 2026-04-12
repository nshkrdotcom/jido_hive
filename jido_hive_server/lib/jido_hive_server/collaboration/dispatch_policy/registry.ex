defmodule JidoHiveServer.Collaboration.DispatchPolicy.Registry do
  @moduledoc false

  alias JidoHiveServer.Collaboration.DispatchPolicies.{HumanGate, ResourcePool, RoundRobin}

  @definitions [
    %{
      policy_id: RoundRobin.id(),
      display_name: "Round Robin",
      description: "Cycles available agent participants against canonical assignments.",
      module: RoundRobin
    },
    %{
      policy_id: ResourcePool.id(),
      display_name: "Resource Pool",
      description: "Prefers the least-used available agent participant.",
      module: ResourcePool
    },
    %{
      policy_id: HumanGate.id(),
      display_name: "Human Gate",
      description: "Runs agent assignments, then waits for a linked human contribution.",
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
        config: Map.get(definition.module.definition(), :config, %{})
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
           config: Map.get(definition.module.definition(), :config, %{})
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
