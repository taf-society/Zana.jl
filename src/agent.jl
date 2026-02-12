



"""
    _strip_think_tags(text)

Remove <think>...</think> blocks from model output (common in reasoning models).
"""
function _strip_think_tags(text::Union{String, Nothing})
    isnothing(text) && return nothing
    cleaned = replace(text, r"<think>[\s\S]*?</think>\s*"s => "")
    cleaned = strip(cleaned)
    if isempty(cleaned)
        cleaned = replace(text, r"</?think>" => "")
        cleaned = strip(cleaned)
    end
    return isempty(cleaned) ? nothing : String(cleaned)
end

"""
    ZanaAgent

AI-powered coding copilot agent. Supports both OpenAI-compatible and Ollama backends.
"""
mutable struct ZanaAgent
    config::ZanaConfig
    state::ZanaState
    tools::Vector{Tool}
    system_prompt::String
end

"""
    ZanaAgent(config, working_dir)

Create a ZanaAgent with the given configuration and working directory.
"""
function ZanaAgent(config::ZanaConfig, working_dir::String)
    state = ZanaState(working_dir)
    tools = _create_tools(state, config.max_output_chars)
    model_name = if !isnothing(config.claude)
        config.claude.model
    elseif !isnothing(config.ollama)
        config.ollama.model
    elseif !isnothing(config.llm)
        config.llm.model
    else
        "unknown"
    end
    prompt = build_system_prompt(working_dir, model_name)
    return ZanaAgent(config, state, tools, prompt)
end

"""
    _create_tools(state, max_output_chars)

Create all coding tools for the agent.
"""
function _create_tools(state::ZanaState, max_output_chars::Int)
    return Tool[
        create_read_file_tool(state),
        create_write_file_tool(state),
        create_edit_file_tool(state),
        create_run_bash_tool(state, max_output_chars),
        create_glob_files_tool(state),
        create_grep_code_tool(state, max_output_chars),
        create_list_directory_tool(state),
    ]
end

"""
    execute_tool(agent, name, args)

Execute a tool by name with the given arguments.
"""
function execute_tool(agent::ZanaAgent, name::String, args::Dict)
    for tool in agent.tools
        if tool.name == name
            return tool.fn(args)
        end
    end
    return Dict("error" => "Unknown tool: $name")
end




function _call_backend(agent::ZanaAgent, messages::Vector{Message})
    if !isnothing(agent.config.claude)
        return call_claude(agent.config.claude, messages, agent.tools)
    elseif !isnothing(agent.config.ollama)
        return call_ollama(agent.config.ollama, messages, agent.tools)
    elseif !isnothing(agent.config.llm)
        return call_llm(agent.config.llm, messages, agent.tools)
    else
        error("No LLM backend configured. Set either config.llm, config.ollama, or config.claude.")
    end
end

function _parse_backend(agent::ZanaAgent, response)
    if !isnothing(agent.config.claude)
        return parse_claude_response(response)
    elseif !isnothing(agent.config.ollama)
        return parse_ollama_response(agent.config.ollama, response)
    else
        return parse_llm_response(response)
    end
end

function _extract_usage(agent::ZanaAgent, response)
    input_tokens = 0
    output_tokens = 0

    try
        if !isnothing(agent.config.claude)
            if haskey(response, "usage")
                usage = response["usage"]
                input_tokens = get(usage, "input_tokens", 0)
                output_tokens = get(usage, "output_tokens", 0)
            end
        elseif !isnothing(agent.config.ollama) && !agent.config.ollama.use_openai_compat

            input_tokens = get(response, "prompt_eval_count", 0)
            output_tokens = get(response, "eval_count", 0)
        else

            if haskey(response, "usage")
                usage = response["usage"]
                input_tokens = get(usage, "prompt_tokens", 0)
                output_tokens = get(usage, "completion_tokens", 0)
            end
        end
    catch
    end

    return (input_tokens, output_tokens)
end




"""
    process_turn(agent, user_input; on_event=nothing) -> TurnResult

Process a single conversation turn. Sends the user message to the LLM,
executes any tool calls, and returns the final response.

The optional `on_event` callback receives status updates:
- `(:thinking,)` — LLM is generating a response
- `(:tool_start, name, args)` — a tool is about to execute
- `(:tool_done, exec)` — a tool finished (ToolExecution)
"""
function process_turn(agent::ZanaAgent, user_input::AbstractString; on_event::Union{Function, Nothing}=nothing)
    _emit(args...) = !isnothing(on_event) && on_event(args...)

    push!(agent.state.conversation_history, Message("user", user_input))

    messages = Message[
        Message("system", agent.system_prompt);
        agent.state.conversation_history
    ]

    tool_executions = ToolExecution[]
    total_in = 0
    total_out = 0

    for _round in 1:agent.config.max_tool_rounds
        _emit(:thinking)
        response = _call_backend(agent, messages)
        assistant_msg = _parse_backend(agent, response)

        clean_content = _strip_think_tags(assistant_msg.content)
        assistant_msg = Message("assistant", clean_content, assistant_msg.tool_calls, nothing)

        (in_tok, out_tok) = _extract_usage(agent, response)
        total_in += in_tok
        total_out += out_tok

        if isnothing(assistant_msg.tool_calls) || isempty(assistant_msg.tool_calls)

            push!(agent.state.conversation_history, assistant_msg)

            agent.state.turn_count += 1
            agent.state.total_tokens_in += total_in
            agent.state.total_tokens_out += total_out

            return TurnResult(
                something(assistant_msg.content, ""),
                tool_executions,
                total_in,
                total_out
            )
        end

        push!(messages, assistant_msg)
        push!(agent.state.conversation_history, assistant_msg)

        for tc in assistant_msg.tool_calls
            _emit(:tool_start, tc.name, tc.arguments)
            t_start = time_ns()
            result = execute_tool(agent, tc.name, tc.arguments)
            t_end = time_ns()
            duration_ms = Int(round((t_end - t_start) / 1_000_000))

            result_str = JSON3.write(result)
            exec = ToolExecution(tc.name, tc.arguments, result_str, duration_ms)
            push!(tool_executions, exec)
            _emit(:tool_done, exec)

            tool_msg = format_tool_result(tc.id, result)
            push!(messages, tool_msg)
            push!(agent.state.conversation_history, tool_msg)
        end
    end

    agent.state.turn_count += 1
    agent.state.total_tokens_in += total_in
    agent.state.total_tokens_out += total_out

    return TurnResult(
        "[Reached maximum tool rounds ($(agent.config.max_tool_rounds)). Please continue or refine your request.]",
        tool_executions,
        total_in,
        total_out
    )
end
