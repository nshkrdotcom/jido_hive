defmodule JidoHiveServer.Collaboration.ContributionValidator do
  @moduledoc false

  alias JidoHiveServer.Collaboration.Schema.{Contribution, Room}

  @callback validate(contribution :: Contribution.t(), room :: Room.t()) :: :ok | {:error, term()}
end
