defmodule JidoHiveClient.AgentBackend do
  @moduledoc false

  alias JidoHiveClient.{ChatInput, InterceptedContribution}

  @callback extract_contribution(ChatInput.t(), keyword()) ::
              {:ok, InterceptedContribution.t()} | {:error, term()}
end
