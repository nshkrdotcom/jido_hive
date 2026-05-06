# Jido Hive Skill Engine

Memory-default skill admission, versioning, composition, and invocation gate
logic for Phase G.

The engine stores admission records in memory unless a caller supplies an
explicit durable adapter ref and durable preflight ref. It resolves prompt,
guard, memory, budget, connector, lease, target, trace, and release refs before
declaring an invocation ready for provider work.
