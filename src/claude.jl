




"""
    ClaudeConfig

Configuration for Anthropic Claude API calls.

- `api_key::String` - Anthropic API key
- `model::String` - Model name (default: "claude-sonnet-4-20250514")
- `base_url::String` - API base URL (default: "https://api.anthropic.com")
- `max_tokens::Int` - Maximum tokens in response (default: 8192)
- `temperature::Float64` - Sampling temperature (default: 0.1)
- `api_version::String` - Anthropic API version header (default: "2023-06-01")
"""
Base.@kwdef struct ClaudeConfig
    api_key::String
    model::String = "claude-sonnet-4-20250514"
    base_url::String = "https://api.anthropic.com"
    max_tokens::Int = 8192
    temperature::Float64 = 0.1
    api_version::String = "2023-06-01"
end

"""
    tools_to_claude_format(tools)

Convert Tool objects to Anthropic's tool format.
Anthropic uses flat tool objects with `input_schema` instead of the OpenAI
`{"type":"function","function":{...}}` wrapper.
"""
function tools_to_claude_format(tools::Vector{Tool})
    return [
        Dict(
            "name" => t.name,
            "description" => t.description,
            "input_schema" => t.parameters
        )
        for t in tools
    ]
end

"""
    messages_to_claude_format(messages) -> (system_text, claude_messages)

Convert Message objects to Anthropic Claude API format.

Key differences from OpenAI:
- System messages are extracted and returned separately (top-level `system` param)
- Tool results are sent as `user` role messages with `tool_result` content blocks
- Assistant messages with tool calls become content block arrays
- Consecutive tool results are grouped into a single user message
"""
function messages_to_claude_format(messages::Vector{Message})
    system_parts = String[]
    claude_messages = Dict{String, Any}[]

    for msg in messages
        if msg.role == "system"
            !isnothing(msg.content) && push!(system_parts, msg.content)
            continue
        end

        if msg.role == "tool"
            # Convert tool result to user message with tool_result content block
            tool_result_block = Dict{String, Any}(
                "type" => "tool_result",
                "tool_use_id" => something(msg.tool_call_id, ""),
                "content" => something(msg.content, "")
            )
            # Group consecutive tool results into a single user message
            if !isempty(claude_messages) && claude_messages[end]["role"] == "user" &&
               claude_messages[end]["content"] isa Vector
                push!(claude_messages[end]["content"], tool_result_block)
            else
                push!(claude_messages, Dict{String, Any}(
                    "role" => "user",
                    "content" => Any[tool_result_block]
                ))
            end
            continue
        end

        if msg.role == "assistant"
            if !isnothing(msg.tool_calls) && !isempty(msg.tool_calls)
                # Assistant with tool calls -> content block array
                blocks = Any[]
                if !isnothing(msg.content) && !isempty(msg.content)
                    push!(blocks, Dict{String, Any}("type" => "text", "text" => msg.content))
                end
                for tc in msg.tool_calls
                    push!(blocks, Dict{String, Any}(
                        "type" => "tool_use",
                        "id" => tc.id,
                        "name" => tc.name,
                        "input" => tc.arguments
                    ))
                end
                push!(claude_messages, Dict{String, Any}("role" => "assistant", "content" => blocks))
            else
                push!(claude_messages, Dict{String, Any}(
                    "role" => "assistant",
                    "content" => something(msg.content, "")
                ))
            end
            continue
        end

        # User messages pass through
        push!(claude_messages, Dict{String, Any}(
            "role" => "user",
            "content" => something(msg.content, "")
        ))
    end

    system_text = join(system_parts, "\n\n")
    return (system_text, claude_messages)
end

"""
    call_claude(config, messages, tools)

Make an API call to the Anthropic Claude Messages API.
"""
function call_claude(config::ClaudeConfig, messages::Vector{Message}, tools::Vector{Tool})
    (system_text, claude_messages) = messages_to_claude_format(messages)

    body = Dict{String, Any}(
        "model" => config.model,
        "messages" => claude_messages,
        "max_tokens" => config.max_tokens,
        "temperature" => config.temperature
    )

    if !isempty(system_text)
        body["system"] = system_text
    end

    if !isempty(tools)
        body["tools"] = tools_to_claude_format(tools)
    end

    headers = [
        "x-api-key" => config.api_key,
        "anthropic-version" => config.api_version,
        "Content-Type" => "application/json"
    ]

    response = HTTP.post(
        "$(config.base_url)/v1/messages",
        headers,
        JSON3.write(body);
        status_exception = true
    )

    return JSON3.read(response.body)
end

"""
    parse_claude_response(response)

Parse Anthropic Claude response into a Message.

Iterates `response["content"]` blocks:
- `"text"` blocks are collected into the content string
- `"tool_use"` blocks are collected into ToolCall objects
"""
function parse_claude_response(response)
    content_parts = String[]
    tool_calls = ToolCall[]

    if haskey(response, "content")
        for block in response["content"]
            block_type = block["type"]
            if block_type == "text"
                text = get(block, "text", "")
                if !isempty(text)
                    push!(content_parts, text)
                end
            elseif block_type == "tool_use"
                args = if block["input"] isa AbstractString
                    JSON3.read(block["input"], Dict{String, Any})
                else
                    Dict{String, Any}(String(k) => v for (k, v) in pairs(block["input"]))
                end
                push!(tool_calls, ToolCall(
                    String(block["id"]),
                    String(block["name"]),
                    args
                ))
            end
        end
    end

    content = isempty(content_parts) ? nothing : join(content_parts, "\n")
    tcs = isempty(tool_calls) ? nothing : tool_calls

    return Message("assistant", content, tcs, nothing)
end
