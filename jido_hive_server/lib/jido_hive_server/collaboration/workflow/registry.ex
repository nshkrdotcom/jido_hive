defmodule JidoHiveServer.Collaboration.Workflow.Registry do
  @moduledoc false

  alias JidoHiveServer.Collaboration.Workflows.{ChainOfResponsibility, DefaultRoundRobin}

  @definitions [
    %{
      workflow_id: DefaultRoundRobin.id(),
      module: DefaultRoundRobin,
      description: "Fixed proposal, critique, and resolution round-robin workflow."
    },
    %{
      workflow_id: ChainOfResponsibility.id(),
      module: ChainOfResponsibility,
      description: "Configurable ordered phases executed across the locked participant set."
    }
  ]

  def list do
    Enum.map(@definitions, fn definition ->
      config = definition.module.load_defaults(%{})

      %{
        workflow_id: definition.workflow_id,
        description: definition.description,
        phases: definition.module.stages(config)
      }
    end)
  end

  def fetch(workflow_id) when is_binary(workflow_id) do
    Enum.find_value(@definitions, {:error, :unknown_workflow}, fn definition ->
      if definition.workflow_id == workflow_id do
        config = definition.module.load_defaults(%{})

        {:ok,
         %{
           workflow_id: definition.workflow_id,
           description: definition.description,
           module: definition.module,
           phases: definition.module.stages(config)
         }}
      end
    end)
  end

  def fetch_module(workflow_id) when is_binary(workflow_id) do
    case fetch(workflow_id) do
      {:ok, definition} -> {:ok, definition.module}
      error -> error
    end
  end
end
