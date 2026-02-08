module Bilge

using HTTP
using JSON3
using UUIDs: uuid4

include("types.jl")

include("llm.jl")
include("ollama.jl")

include("config.jl")

include("tools.jl")

include("system_prompt.jl")

include("agent.jl")

include("repl.jl")

export bilge
export BilgeAgent, BilgeConfig, BilgeState, TurnResult, ToolExecution
export LLMConfig, OllamaConfig
export process_turn
export list_ollama_models, check_ollama_connection

end # module Bilge
