



"""
    LLMConfig

Configuration for LLM API calls.
"""
Base.@kwdef struct LLMConfig
    api_key::String
    model::String = "gpt-4o"
    base_url::String = "https://api.openai.com/v1"
    max_tokens::Int = 4096
    temperature::Float64 = 0.1
    frequency_penalty::Float64 = 0.0
end

"""
    tools_to_openai_format(tools)

Convert Tool objects to OpenAI function calling format.
"""
function tools_to_openai_format(tools::Vector{Tool})
    return [
        Dict(
            "type" => "function",
            "function" => Dict(
                "name" => t.name,
                "description" => t.description,
                "parameters" => t.parameters
            )
        )
        for t in tools
    ]
end

"""
    messages_to_openai_format(messages)

Convert Message objects to OpenAI API format.
"""
function messages_to_openai_format(messages::Vector{Message})
    result = Dict{String, Any}[]

    for msg in messages
        d = Dict{String, Any}("role" => msg.role)

        if !isnothing(msg.content)
            d["content"] = msg.content
        elseif msg.role == "assistant"

            d["content"] = nothing
        end

        if !isnothing(msg.tool_calls)
            d["tool_calls"] = [
                Dict(
                    "id" => tc.id,
                    "type" => "function",
                    "function" => Dict(
                        "name" => tc.name,
                        "arguments" => JSON3.write(tc.arguments)
                    )
                )
                for tc in msg.tool_calls
            ]
        end

        if !isnothing(msg.tool_call_id)
            d["tool_call_id"] = msg.tool_call_id
        end

        push!(result, d)
    end

    return result
end

"""
    call_llm(config, messages, tools)

Make an API call to the LLM.
"""
function call_llm(config::LLMConfig, messages::Vector{Message}, tools::Vector{Tool})
    tools_spec = tools_to_openai_format(tools)
    messages_spec = messages_to_openai_format(messages)

    body = Dict(
        "model" => config.model,
        "messages" => messages_spec,
        "max_tokens" => config.max_tokens,
        "temperature" => config.temperature,
        "frequency_penalty" => config.frequency_penalty
    )

    if !isempty(tools)
        body["tools"] = tools_spec
        body["tool_choice"] = "auto"
    end

    headers = [
        "Authorization" => "Bearer $(config.api_key)",
        "Content-Type" => "application/json"
    ]

    response = HTTP.post(
        "$(config.base_url)/chat/completions",
        headers,
        JSON3.write(body);
        status_exception = true
    )

    return JSON3.read(response.body)
end

"""
    parse_llm_response(response)

Parse LLM response into Message and tool calls.
"""
function parse_llm_response(response)
    choice = response["choices"][1]
    message = choice["message"]

    content = get(message, "content", nothing)
    tool_calls = nothing

    if haskey(message, "tool_calls") && !isnothing(message["tool_calls"])
        tool_calls = ToolCall[]
        for tc in message["tool_calls"]
            push!(tool_calls, ToolCall(
                tc["id"],
                tc["function"]["name"],
                JSON3.read(tc["function"]["arguments"], Dict{String, Any})
            ))
        end
    end

    return Message("assistant", content, tool_calls, nothing)
end

"""
    format_tool_result(tool_call_id, result)

Create a tool result message.
"""
function format_tool_result(tool_call_id::String, result::Dict)
    return Message("tool", JSON3.write(result), nothing, tool_call_id)
end
