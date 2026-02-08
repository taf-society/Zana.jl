



"""
    OllamaConfig

Configuration for Ollama API calls.

Supports both the native Ollama API (`/api/chat`) and the OpenAI-compatible
endpoint (`/v1/chat/completions`).

- `model::String` - Model name (e.g., "llama3.1", "qwen2.5", "mistral")
- `host::String` - Ollama server address (default: "http://localhost:11434")
- `max_tokens::Int` - Maximum tokens in response (default: 4096)
- `temperature::Float64` - Sampling temperature (default: 0.1)
- `use_openai_compat::Bool` - Use OpenAI-compatible endpoint (default: false)
"""
Base.@kwdef struct OllamaConfig
    model::String = "llama3.1"
    host::String = "http://localhost:11434"
    max_tokens::Int = 4096
    temperature::Float64 = 0.1
    use_openai_compat::Bool = false
end




"""
    tools_to_ollama_format(tools)

Convert Tool objects to Ollama's native tool calling format.
"""
function tools_to_ollama_format(tools::Vector{Tool})
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
    messages_to_ollama_format(messages)

Convert Message objects to Ollama's native message format.
"""
function messages_to_ollama_format(messages::Vector{Message})
    result = Dict{String, Any}[]

    for msg in messages
        d = Dict{String, Any}("role" => msg.role)

        if !isnothing(msg.content)
            d["content"] = msg.content
        elseif msg.role == "assistant"
            d["content"] = ""
        end

        if !isnothing(msg.tool_calls)
            d["tool_calls"] = [
                Dict(
                    "function" => Dict(
                        "name" => tc.name,
                        "arguments" => tc.arguments
                    )
                )
                for tc in msg.tool_calls
            ]
        end

        push!(result, d)
    end

    return result
end

"""
    call_ollama(config, messages, tools)

Make an API call to Ollama using the native `/api/chat` endpoint.
"""
function call_ollama(config::OllamaConfig, messages::Vector{Message}, tools::Vector{Tool})
    if config.use_openai_compat
        return call_ollama_openai_compat(config, messages, tools)
    end

    messages_spec = messages_to_ollama_format(messages)

    body = Dict{String, Any}(
        "model" => config.model,
        "messages" => messages_spec,
        "stream" => false,
        "options" => Dict(
            "temperature" => config.temperature,
            "num_predict" => config.max_tokens
        )
    )

    if !isempty(tools)
        body["tools"] = tools_to_ollama_format(tools)
    end

    headers = ["Content-Type" => "application/json"]

    response = HTTP.post(
        "$(config.host)/api/chat",
        headers,
        JSON3.write(body);
        status_exception = true
    )

    return JSON3.read(response.body)
end

"""
    call_ollama_openai_compat(config, messages, tools)

Make an API call using Ollama's OpenAI-compatible endpoint (`/v1/chat/completions`).
"""
function call_ollama_openai_compat(config::OllamaConfig, messages::Vector{Message}, tools::Vector{Tool})
    tools_spec = tools_to_openai_format(tools)
    messages_spec = messages_to_openai_format(messages)

    body = Dict{String, Any}(
        "model" => config.model,
        "messages" => messages_spec,
        "max_tokens" => config.max_tokens,
        "temperature" => config.temperature
    )

    if !isempty(tools)
        body["tools"] = tools_spec
        body["tool_choice"] = "auto"
    end

    headers = [
        "Authorization" => "Bearer ollama",
        "Content-Type" => "application/json"
    ]

    response = HTTP.post(
        "$(config.host)/v1/chat/completions",
        headers,
        JSON3.write(body);
        status_exception = true
    )

    return JSON3.read(response.body)
end

"""
    _extract_tool_calls_from_text(content)

Fallback parser: extract tool calls from text content when models embed them
in their output instead of using the native tool calling API. Handles common
patterns like <tool_call>...</tool_call> and ```json {"name":...} ``` blocks.

Returns (cleaned_content, tool_calls) where tool_calls may be nothing.
"""
function _extract_tool_calls_from_text(content::AbstractString)
    tool_calls = ToolCall[]

    for m in eachmatch(r"<tool_call>\s*(\{.*?\})\s*</tool_call>"s, content)
        try
            obj = JSON3.read(m.captures[1], Dict{String, Any})
            name = get(obj, "name", nothing)
            args = get(obj, "arguments", Dict{String, Any}())
            if !isnothing(name)
                if args isa AbstractString
                    args = JSON3.read(args, Dict{String, Any})
                else
                    args = Dict{String, Any}(String(k) => v for (k, v) in pairs(args))
                end
                push!(tool_calls, ToolCall(string(uuid4()), String(name), args))
            end
        catch
        end
    end

    if isempty(tool_calls)
        for m in eachmatch(r"\{[^{}]*\"name\"\s*:\s*\"(\w+)\"[^{}]*\"arguments\"\s*:\s*(\{[^}]*\})[^{}]*\}"s, content)
            try
                name = String(m.captures[1])
                args = JSON3.read(m.captures[2], Dict{String, Any})
                push!(tool_calls, ToolCall(string(uuid4()), name, args))
            catch
            end
        end
    end

    if isempty(tool_calls)
        return (content, nothing)
    end

    cleaned = replace(content, r"<tool_call>\s*\{.*?\}\s*</tool_call>"s => "")
    cleaned = strip(cleaned)
    if isempty(cleaned)
        cleaned = nothing
    end

    return (cleaned, tool_calls)
end

"""
    parse_ollama_response(config, response)

Parse Ollama response into Message and tool calls.
Handles both native and OpenAI-compatible formats.
Falls back to text parsing if the model embeds tool calls in content.
"""
function parse_ollama_response(config::OllamaConfig, response)
    if config.use_openai_compat

        return parse_llm_response(response)
    end

    message = response["message"]

    content = get(message, "content", nothing)
    if content isa AbstractString && isempty(strip(content))
        content = nothing
    end

    tool_calls = nothing

    if haskey(message, "tool_calls") && !isnothing(message["tool_calls"])
        tc_list = message["tool_calls"]
        if length(tc_list) > 0
            tool_calls = ToolCall[]
            for tc in tc_list
                fn = tc["function"]

                args = if fn["arguments"] isa AbstractString
                    JSON3.read(fn["arguments"], Dict{String, Any})
                else
                    Dict{String, Any}(String(k) => v for (k, v) in pairs(fn["arguments"]))
                end

                push!(tool_calls, ToolCall(
                    string(uuid4()),  # Ollama native API doesn't provide tool call IDs
                    String(fn["name"]),
                    args
                ))
            end
        end
    end

    if isnothing(tool_calls) && !isnothing(content)
        (content, tool_calls) = _extract_tool_calls_from_text(content)
    end

    return Message("assistant", content, tool_calls, nothing)
end




"""
    list_ollama_models(; host="http://localhost:11434")

List available models on the Ollama server.

- `Vector{String}` of model names
"""
function list_ollama_models(; host::String = "http://localhost:11434")
    response = HTTP.get("$(host)/api/tags"; status_exception = true)
    data = JSON3.read(response.body)
    models = String[]
    if haskey(data, "models")
        for model in data["models"]
            push!(models, String(model["name"]))
        end
    end
    return models
end

"""
    check_ollama_connection(; host="http://localhost:11434")

Check if Ollama server is running and accessible.

- `Bool` - true if server is reachable
"""
function check_ollama_connection(; host::String = "http://localhost:11434")
    try
        HTTP.get(host; status_exception = true, connect_timeout = 5)
        return true
    catch
        return false
    end
end
