module Zana

using HTTP
using JSON3
using UUIDs: uuid4

include("types.jl")

include("llm.jl")
include("ollama.jl")
include("claude.jl")

include("config.jl")

include("tools.jl")

include("system_prompt.jl")

include("agent.jl")

include("repl.jl")

export zana
export ZanaAgent, ZanaConfig, ZanaState, TurnResult, ToolExecution
export LLMConfig, OllamaConfig, ClaudeConfig
export process_turn
export list_ollama_models, check_ollama_connection

end # module Zana
