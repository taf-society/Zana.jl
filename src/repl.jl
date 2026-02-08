



"""
    bilge(; api_key, model, base_url, ollama, host, use_openai_compat, working_dir)

Start the Bilge interactive coding copilot.

- `api_key::String` - OpenAI API key (default: ENV["OPENAI_API_KEY"])
- `model::String` - Model name (default: "gpt-4o" or "llama3.1" for Ollama)
- `base_url::String` - API base URL (default: "https://api.openai.com/v1")
- `ollama::Bool` - Use Ollama backend (default: false)
- `host::String` - Ollama host (default: "http://localhost:11434")
- `use_openai_compat::Bool` - Use Ollama's OpenAI-compatible endpoint (default: false)
- `working_dir::String` - Working directory (default: pwd())

```julia
using Bilge

bilge(ollama=true, model="qwen3")

bilge(api_key="sk-...")

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

    working_dir = abspath(working_dir)
    if !isdir(working_dir)
        println("\n  Error: Working directory not found: $working_dir\n")
        return
    end

    agent = BilgeAgent(config, working_dir)

    display_model = if ollama
        agent.config.ollama.model
    else
        agent.config.llm.model
    end

    println()
    println("  \e[1;36mBilge\e[0m — Julia Coding Copilot")
    println("  Model: \e[33m$display_model\e[0m")
    println("  Working directory: \e[32m$working_dir\e[0m")
    println("  Type /help for commands, /exit to quit")
    println()

    while true
        input = _read_input(agent.state)

        if isnothing(input)
            println("Goodbye!")
            break
        end

        input = strip(input)
        if isempty(input)
            continue
        end

        if startswith(input, "/")
            should_continue = _handle_slash_command(agent, input)
            if !should_continue
                break
            end
            continue
        end

        try
            spinner_active = false

            function on_event(args...)
                event = args[1]
                if event === :thinking
                    if !spinner_active
                        spinner_active = true
                        printstyled("\n  Thinking...", color=:dark_gray)
                        flush(stdout)
                    else

                        print("\r\e[2K")
                        printstyled("  Thinking...", color=:dark_gray)
                        flush(stdout)
                    end
                elseif event === :tool_start

                    print("\r\e[2K")
                    flush(stdout)
                elseif event === :tool_done
                    exec = args[2]
                    _print_tool_summary(exec)
                    flush(stdout)
                end
            end

            result = process_turn(agent, input; on_event=on_event)

            if spinner_active
                print("\r\e[2K")
            end

            println()
            println(result.response)
            println()

            if result.input_tokens > 0 || result.output_tokens > 0
                printstyled("  [tokens: $(result.input_tokens) in / $(result.output_tokens) out]\n",
                           color=:dark_gray)
            end
        catch e
            print("\r\e[2K")  # Clear spinner if active
            println()
            printstyled("  Error: ", color=:red, bold=true)
            println(sprint(showerror, e))
            println()
        end
    end
end

"""
    _read_line_raw(prompt, color, history) -> Union{String, Nothing}

Read a single line from a TTY with arrow key history navigation.
Supports: Up/Down (history), Left/Right (cursor), Home/End, Backspace, Delete,
Ctrl-A/E/K/U/W/L, and UTF-8 input. Returns nothing on Ctrl-C or Ctrl-D.
"""
function _read_line_raw(prompt::String, color::Symbol, history::Vector{String})
    printstyled(prompt, color=color, bold=true)
    flush(stdout)

    ret = ccall(:uv_tty_set_mode, Cint, (Ptr{Cvoid}, Cint), stdin.handle, Int32(1))
    if ret != 0
        try
            return readline(stdin)
        catch e
            (e isa InterruptException || e isa Base.IOError) && return nothing
            rethrow(e)
        end
    end

    buf = Char[]
    cursor_pos = 0
    hist_idx = length(history) + 1
    saved_input = ""

    function redraw()
        print("\r\e[2K")
        printstyled(prompt, color=color, bold=true)
        print(String(buf))
        chars_after = length(buf) - cursor_pos
        if chars_after > 0
            print("\e[$(chars_after)D")
        end
        flush(stdout)
    end

    try
        while true
            b = read(stdin, UInt8)

            if b == 0x0d || b == 0x0a  # Enter
                print('\n')
                return String(buf)

            elseif b == 0x03  # Ctrl-C
                print('\n')
                return nothing

            elseif b == 0x04  # Ctrl-D
                if isempty(buf)
                    print('\n')
                    return nothing
                end

            elseif b == 0x7f || b == 0x08  # Backspace
                if cursor_pos > 0
                    deleteat!(buf, cursor_pos)
                    cursor_pos -= 1
                    redraw()
                end

            elseif b == 0x1b  # ESC
                b2 = read(stdin, UInt8)
                if b2 == UInt8('[')
                    b3 = read(stdin, UInt8)
                    if b3 == UInt8('A')  # Up
                        if hist_idx > 1
                            if hist_idx == length(history) + 1
                                saved_input = String(buf)
                            end
                            hist_idx -= 1
                            empty!(buf)
                            append!(buf, collect(history[hist_idx]))
                            cursor_pos = length(buf)
                            redraw()
                        end
                    elseif b3 == UInt8('B')  # Down
                        if hist_idx <= length(history)
                            hist_idx += 1
                            empty!(buf)
                            if hist_idx > length(history)
                                append!(buf, collect(saved_input))
                            else
                                append!(buf, collect(history[hist_idx]))
                            end
                            cursor_pos = length(buf)
                            redraw()
                        end
                    elseif b3 == UInt8('C')  # Right
                        if cursor_pos < length(buf)
                            cursor_pos += 1
                            print("\e[C")
                            flush(stdout)
                        end
                    elseif b3 == UInt8('D')  # Left
                        if cursor_pos > 0
                            cursor_pos -= 1
                            print("\e[D")
                            flush(stdout)
                        end
                    elseif b3 == UInt8('H')  # Home
                        cursor_pos = 0
                        redraw()
                    elseif b3 == UInt8('F')  # End
                        cursor_pos = length(buf)
                        redraw()
                    elseif b3 == UInt8('3')  # Delete (ESC [ 3 ~)
                        b4 = read(stdin, UInt8)
                        if b4 == UInt8('~') && cursor_pos < length(buf)
                            deleteat!(buf, cursor_pos + 1)
                            redraw()
                        end
                    end
                end

            elseif b == 0x01  # Ctrl-A (Home)
                cursor_pos = 0
                redraw()

            elseif b == 0x05  # Ctrl-E (End)
                cursor_pos = length(buf)
                redraw()

            elseif b == 0x0b  # Ctrl-K (Kill to end of line)
                if cursor_pos < length(buf)
                    deleteat!(buf, (cursor_pos + 1):length(buf))
                    redraw()
                end

            elseif b == 0x15  # Ctrl-U (Kill to start of line)
                if cursor_pos > 0
                    deleteat!(buf, 1:cursor_pos)
                    cursor_pos = 0
                    redraw()
                end

            elseif b == 0x17  # Ctrl-W (Delete word backward)
                if cursor_pos > 0
                    new_pos = cursor_pos
                    while new_pos > 0 && buf[new_pos] == ' '
                        new_pos -= 1
                    end
                    while new_pos > 0 && buf[new_pos] != ' '
                        new_pos -= 1
                    end
                    deleteat!(buf, (new_pos + 1):cursor_pos)
                    cursor_pos = new_pos
                    redraw()
                end

            elseif b == 0x0c  # Ctrl-L (Clear screen)
                print("\e[2J\e[H")
                redraw()

            elseif b == 0x09  # Tab - ignore
                continue

            elseif b >= 0x20 && b < 0x7f  # Printable ASCII
                cursor_pos += 1
                insert!(buf, cursor_pos, Char(b))
                redraw()

            elseif b >= 0xc0  # UTF-8 multi-byte start
                n_bytes = b < 0xe0 ? 2 : b < 0xf0 ? 3 : 4
                bytes = UInt8[b]
                for _ in 2:n_bytes
                    push!(bytes, read(stdin, UInt8))
                end
                try
                    ch = first(String(bytes))
                    cursor_pos += 1
                    insert!(buf, cursor_pos, ch)
                    redraw()
                catch
                end
            end
        end
    catch e
        if e isa InterruptException
            print('\n')
            return nothing
        end
        rethrow(e)
    finally
        ccall(:uv_tty_set_mode, Cint, (Ptr{Cvoid}, Cint), stdin.handle, Int32(0))
    end
end

"""
    _read_input(state)

Read user input with history navigation and multi-line support.
Returns nothing on EOF or Ctrl-C.
"""
function _read_input(state::BilgeState)
    if stdin isa Base.TTY
        return _read_input_tty(state)
    else
        return _read_input_pipe()
    end
end

function _read_input_tty(state::BilgeState)
    lines = String[]

    while true
        prompt = isempty(lines) ? "bilge> " : "  ...> "
        history = isempty(lines) ? state.input_history : String[]
        line = _read_line_raw(prompt, :cyan, history)

        if isnothing(line)
            return isempty(lines) ? nothing : join(lines, "\n")
        end

        if endswith(line, "\\")
            push!(lines, line[1:end-1])
        else
            push!(lines, line)
            break
        end
    end

    result = join(lines, "\n")
    stripped = strip(result)
    if !isempty(stripped)
        push!(state.input_history, stripped)
    end
    return result
end

function _read_input_pipe()
    printstyled("bilge> ", color=:cyan, bold=true)
    flush(stdout)
    lines = String[]

    while true
        line = try
            readline(stdin)
        catch e
            (e isa InterruptException || e isa Base.IOError) && return nothing
            rethrow(e)
        end

        if isempty(lines) && isempty(line)
            if !isopen(stdin)
                return nothing
            end
            if eof(stdin)
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
function _handle_slash_command(agent::BilgeAgent, input::AbstractString)
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

                agent.tools = _create_tools(agent.state, agent.config.max_output_chars)
                model_name = if !isnothing(agent.config.ollama)
                    agent.config.ollama.model
                elseif !isnothing(agent.config.llm)
                    agent.config.llm.model
                else
                    "unknown"
                end
                agent.system_prompt = build_system_prompt(new_dir, model_name)
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
