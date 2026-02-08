# ============================================================================
# REPL Interface for Bilge.jl
# ============================================================================

"""
    bilge(; api_key, model, base_url, ollama, host, use_openai_compat, working_dir)

Start the Bilge interactive coding copilot.

# Keyword Arguments
- `api_key::String` - OpenAI API key (default: ENV["OPENAI_API_KEY"])
- `model::String` - Model name (default: "gpt-4o" or "llama3.1" for Ollama)
- `base_url::String` - API base URL (default: "https://api.openai.com/v1")
- `ollama::Bool` - Use Ollama backend (default: false)
- `host::String` - Ollama host (default: "http://localhost:11434")
- `use_openai_compat::Bool` - Use Ollama's OpenAI-compatible endpoint (default: false)
- `working_dir::String` - Working directory (default: pwd())

# Example
```julia
using Bilge

# Using Ollama
bilge(ollama=true, model="qwen3")

# Using OpenAI
bilge(api_key="sk-...")

# Using custom OpenAI-compatible API
bilge(api_key="key", base_url="https://api.example.com/v1", model="my-model")
```
"""
function bilge(;
    api_key::Union{String, Nothing} = nothing,
    model::Union{String, Nothing} = nothing,
    base_url::String = "https://api.openai.com/v1",
    ollama::Bool = false,
    host::String = "http://localhost:11434",
    use_openai_compat::Bool = false,
    working_dir::String = pwd()
)
    # Build config
    config = if ollama
        model_name = something(model, "llama3.1")
        ollama_cfg = OllamaConfig(
            model = model_name,
            host = host,
            use_openai_compat = use_openai_compat
        )
        BilgeConfig(ollama = ollama_cfg)
    else
        key = something(api_key, get(ENV, "OPENAI_API_KEY", nothing))
        if isnothing(key)
            println("\n  Error: No API key provided.")
            println("  Set OPENAI_API_KEY or pass api_key= keyword.\n")
            return
        end
        model_name = something(model, "gpt-4o")
        llm_cfg = LLMConfig(
            api_key = key,
            model = model_name,
            base_url = base_url
        )
        BilgeConfig(llm = llm_cfg)
    end

    # Resolve working directory
    working_dir = abspath(working_dir)
    if !isdir(working_dir)
        println("\n  Error: Working directory not found: $working_dir\n")
        return
    end

    # Create agent
    agent = BilgeAgent(config, working_dir)

    # Determine model name for display
    display_model = if ollama
        agent.config.ollama.model
    else
        agent.config.llm.model
    end

    # Print banner
    println()
    println("  \e[1;36mBilge\e[0m — Julia Coding Copilot")
    println("  Model: \e[33m$display_model\e[0m")
    println("  Working directory: \e[32m$working_dir\e[0m")
    println("  Type /help for commands, /exit to quit")
    println()

    # Interactive loop
    while true
        # Prompt
        printstyled("bilge> ", color=:cyan, bold=true)
        flush(stdout)
        input = _read_input()

        if isnothing(input)
            # EOF
            println("\nGoodbye!")
            break
        end

        input = strip(input)
        if isempty(input)
            continue
        end

        # Handle slash commands
        if startswith(input, "/")
            should_continue = _handle_slash_command(agent, input)
            if !should_continue
                break
            end
            continue
        end

        # Process normal input
        try
            result = process_turn(agent, input)

            # Show tool execution summary
            if !isempty(result.tool_executions)
                println()
                for exec in result.tool_executions
                    _print_tool_summary(exec)
                end
            end

            # Show response
            println()
            println(result.response)
            println()

            # Show token usage (subtle)
            if result.input_tokens > 0 || result.output_tokens > 0
                printstyled("  [tokens: $(result.input_tokens) in / $(result.output_tokens) out]\n",
                           color=:dark_gray)
            end
        catch e
            println()
            printstyled("  Error: ", color=:red, bold=true)
            println(sprint(showerror, e))
            println()
        end
    end
end

"""
    _read_input()

Read user input, supporting multi-line with trailing backslash.
Returns nothing on EOF.
"""
function _read_input()
    lines = String[]

    while true
        line = try
            readline(stdin)
        catch e
            if e isa InterruptException
                return nothing
            end
            if e isa Base.IOError
                return nothing
            end
            rethrow(e)
        end

        # Detect true EOF: only when stdin is actually closed.
        # Avoid eof(stdin) on a TTY — it can return true spuriously
        # in the Julia REPL, causing the prompt to exit immediately.
        if isempty(lines) && isempty(line)
            if !isopen(stdin)
                return nothing
            end
            if !(stdin isa Base.TTY) && eof(stdin)
                return nothing
            end
        end

        if endswith(line, "\\")
            push!(lines, line[1:end-1])
            printstyled("  ...> ", color=:cyan)
            flush(stdout)
        else
            push!(lines, line)
            break
        end
    end

    return join(lines, "\n")
end

"""
    _handle_slash_command(agent, input) -> Bool

Handle a slash command. Returns true to continue the REPL, false to exit.
"""
function _handle_slash_command(agent::BilgeAgent, input::String)
    cmd = lowercase(strip(input))
    parts = split(cmd, r"\s+"; limit=2)
    command = parts[1]

    if command == "/exit" || command == "/quit"
        println("\nGoodbye!")
        return false

    elseif command == "/clear"
        agent.state.conversation_history = Message[]
        agent.state.turn_count = 0
        println("  Conversation cleared.")
        println()
        return true

    elseif command == "/history"
        _show_history(agent)
        return true

    elseif command == "/tokens"
        println()
        println("  Total tokens: $(agent.state.total_tokens_in) in / $(agent.state.total_tokens_out) out")
        println("  Turns: $(agent.state.turn_count)")
        println()
        return true

    elseif command == "/cd"
        if length(parts) < 2
            println("  Usage: /cd PATH")
        else
            new_dir = abspath(strip(String(parts[2])))
            if isdir(new_dir)
                agent.state.working_directory = new_dir
                # Rebuild tools and system prompt with new working directory
                agent.tools = _create_tools(agent.state, agent.config.max_output_chars)
                agent.system_prompt = build_system_prompt(new_dir)
                println("  Working directory: $new_dir")
            else
                println("  Error: Not a directory: $new_dir")
            end
        end
        println()
        return true

    elseif command == "/help"
        println()
        println("  \e[1mCommands:\e[0m")
        println("  /exit, /quit   Exit Bilge")
        println("  /clear         Clear conversation history")
        println("  /history       Show conversation history")
        println("  /tokens        Show token usage")
        println("  /cd PATH       Change working directory")
        println("  /help          Show this help")
        println()
        println("  \e[1mTips:\e[0m")
        println("  - Use \\ at end of line for multi-line input")
        println("  - Ask about code, request changes, run commands")
        println()
        return true

    else
        println("  Unknown command: $command (type /help for available commands)")
        println()
        return true
    end
end

"""
    _show_history(agent)

Display a summary of the conversation history.
"""
function _show_history(agent::BilgeAgent)
    println()
    if isempty(agent.state.conversation_history)
        println("  No conversation history.")
    else
        for (i, msg) in enumerate(agent.state.conversation_history)
            role = msg.role
            if role == "user"
                content = something(msg.content, "")
                preview = length(content) > 80 ? content[1:80] * "..." : content
                printstyled("  [$i] user: ", color=:green)
                println(preview)
            elseif role == "assistant"
                if !isnothing(msg.tool_calls) && !isempty(msg.tool_calls)
                    tools_used = join([tc.name for tc in msg.tool_calls], ", ")
                    printstyled("  [$i] assistant: ", color=:blue)
                    println("[tools: $tools_used]")
                elseif !isnothing(msg.content)
                    preview = length(msg.content) > 80 ? msg.content[1:80] * "..." : msg.content
                    printstyled("  [$i] assistant: ", color=:blue)
                    println(preview)
                end
            elseif role == "tool"
                # Skip tool results in history view for brevity
            end
        end
    end
    println()
end

"""
    _print_tool_summary(exec)

Print a brief summary of a tool execution.
"""
function _print_tool_summary(exec::ToolExecution)
    # Build a brief context string
    context = if exec.tool_name == "read_file"
        path = get(exec.arguments, "file_path", "")
        "  $path"
    elseif exec.tool_name == "write_file"
        path = get(exec.arguments, "file_path", "")
        "  $path"
    elseif exec.tool_name == "edit_file"
        path = get(exec.arguments, "file_path", "")
        "  $path"
    elseif exec.tool_name == "run_bash"
        cmd = get(exec.arguments, "command", "")
        preview = length(cmd) > 60 ? cmd[1:60] * "..." : cmd
        "  $preview"
    elseif exec.tool_name == "glob_files"
        pat = get(exec.arguments, "pattern", "")
        "  $pat"
    elseif exec.tool_name == "grep_code"
        pat = get(exec.arguments, "pattern", "")
        "  /$pat/"
    elseif exec.tool_name == "list_directory"
        path = get(exec.arguments, "path", ".")
        "  $path"
    else
        ""
    end

    duration = exec.duration_ms < 1000 ? "$(exec.duration_ms)ms" : "$(round(exec.duration_ms / 1000; digits=1))s"
    printstyled("  ⚙ $(exec.tool_name)", color=:yellow)
    printstyled(context, color=:dark_gray)
    printstyled("  ($duration)\n", color=:dark_gray)
end
