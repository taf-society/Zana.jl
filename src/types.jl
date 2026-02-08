



"""
    Tool

Represents a callable tool that the LLM can invoke.
"""
struct Tool
    name::String
    description::String
    parameters::Dict{String, Any}
    fn::Function
end

"""
    ToolCall

Represents a tool call request from the LLM.
"""
struct ToolCall
    id::String
    name::String
    arguments::Dict{String, Any}
end

"""
    Message

A message in the conversation.
"""
struct Message
    role::String  # "system", "user", "assistant", "tool"
    content::Union{String, Nothing}
    tool_calls::Union{Vector{ToolCall}, Nothing}
    tool_call_id::Union{String, Nothing}
end

Message(role::AbstractString, content::AbstractString) = Message(String(role), String(content), nothing, nothing)

