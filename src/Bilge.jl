module Bilge

using HTTP
using JSON3
using UUIDs: uuid4

# Base types (Tool, ToolCall, Message)
include("types.jl")

# LLM backends
include("llm.jl")
include("ollama.jl")

# Bilge-specific types (depends on LLMConfig, OllamaConfig)
include("config.jl")

# Tools
include("tools.jl")

# System prompt
include("system_prompt.jl")

# Agent
include("agent.jl")

# REPL interface
include("repl.jl")

# Exports
export bilge
export BilgeAgent, BilgeConfig, BilgeState, TurnResult, ToolExecution
export LLMConfig, OllamaConfig
export process_turn
export list_ollama_models, check_ollama_connection

end # module Bilge
