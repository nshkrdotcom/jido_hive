defmodule JidoHiveServer.Collaboration.RoomAgent do
  @moduledoc false

  use Jido.Agent,
    name: "room_agent",
    description: "Pure room-state authority for the first collaboration slice",
    schema: [
      room_id: [type: :string, required: true],
      session_id: [type: :string, required: true],
      brief: [type: :string, required: true],
      rules: [type: {:list, :string}, default: []],
      participants: [type: {:list, :map}, default: []],
      turns: [type: {:list, :map}, default: []],
      context_entries: [type: {:list, :map}, default: []],
      disputes: [type: {:list, :map}, default: []],
      current_turn: [type: :map, default: %{}],
      execution_plan: [type: :map, default: %{}],
      status: [type: :string, default: "idle"],
      phase: [type: :string, default: "idle"],
      round: [type: :integer, default: 0],
      next_entry_seq: [type: :integer, default: 1],
      next_dispute_seq: [type: :integer, default: 1]
    ]
end
