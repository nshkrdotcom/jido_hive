# Jido Hive Skill Contracts

Publishable skill contracts for Phase G.

The package defines manifest, capability binding, composition, version, and
invocation intent structs. Contract data is ref-only: prompt, memory, provider,
secret, credential, authorization, and private-state bodies are rejected before
the manifest can be admitted.

External packages should depend on this package when they need to author or
validate skill manifests without importing runtime internals.
