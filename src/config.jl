



"""
    ZanaConfig

Configuration for the Zana coding copilot.
"""
Base.@kwdef struct ZanaConfig
    llm::Union{LLMConfig, Nothing} = nothing
    ollama::Union{OllamaConfig, Nothing} = nothing
    claude::Union{ClaudeConfig, Nothing} = nothing
    max_tool_rounds::Int = 50
    max_output_chars::Int = 100_000
end

"""
    ToolExecution

Record of a single tool execution.
"""
struct ToolExecution
    tool_name::String
    arguments::Dict{String, Any}
    result::String
    duration_ms::Int
end

"""
    TurnResult

Result of a single conversation turn.
"""
struct TurnResult
    response::String
    tool_executions::Vector{ToolExecution}
    input_tokens::Int
    output_tokens::Int
end

"""
    ZanaState

Mutable state maintained across the coding session.
"""
mutable struct ZanaState
    working_directory::String
    conversation_history::Vector{Message}
    input_history::Vector{String}
    turn_count::Int
    total_tokens_in::Int
    total_tokens_out::Int
end

ZanaState(working_dir::String) = ZanaState(working_dir, Message[], String[], 0, 0, 0)
