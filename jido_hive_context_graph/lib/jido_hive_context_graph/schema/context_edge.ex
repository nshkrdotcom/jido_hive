defmodule JidoHiveContextGraph.Schema.ContextEdge do
  @moduledoc false

  @type edge_type ::
          :derives_from
          | :references
          | :contradicts
          | :resolves
          | :supersedes
          | :supports
          | :blocks

  @type t :: %__MODULE__{
          from_id: String.t(),
          to_id: String.t(),
          type: edge_type(),
          inserted_at: DateTime.t()
        }

  defstruct [:from_id, :to_id, :type, :inserted_at]
end
