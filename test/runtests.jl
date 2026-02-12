using Test
using Zana

@testset "Zana.jl" begin

    @testset "Types" begin
        @testset "Message" begin
            msg = Zana.Message("user", "hello")
            @test msg.role == "user"
            @test msg.content == "hello"
            @test isnothing(msg.tool_calls)
            @test isnothing(msg.tool_call_id)
        end

        @testset "ToolCall" begin
            tc = Zana.ToolCall("id-1", "read_file", Dict{String, Any}("file_path" => "test.jl"))
            @test tc.id == "id-1"
            @test tc.name == "read_file"
            @test tc.arguments["file_path"] == "test.jl"
        end

        @testset "ZanaConfig" begin
            cfg = ZanaConfig()
            @test isnothing(cfg.llm)
            @test isnothing(cfg.ollama)
            @test cfg.max_tool_rounds == 50
            @test cfg.max_output_chars == 100_000
        end

        @testset "ZanaState" begin
            state = ZanaState("/tmp")
            @test state.working_directory == "/tmp"
            @test isempty(state.conversation_history)
            @test state.turn_count == 0
            @test state.total_tokens_in == 0
            @test state.total_tokens_out == 0
        end

        @testset "TurnResult" begin
            tr = TurnResult("response", ToolExecution[], 100, 50)
            @test tr.response == "response"
            @test isempty(tr.tool_executions)
            @test tr.input_tokens == 100
            @test tr.output_tokens == 50
        end

        @testset "ToolExecution" begin
            te = ToolExecution("read_file", Dict{String, Any}("file_path" => "x.jl"), "{}", 42)
            @test te.tool_name == "read_file"
            @test te.duration_ms == 42
        end
    end

    @testset "Tools" begin
        test_dir = mktempdir()
        state = ZanaState(test_dir)

        @testset "read_file" begin
            # Create a test file
            test_file = joinpath(test_dir, "test.txt")
            write(test_file, "line1\nline2\nline3\nline4\nline5\n")

            tool = Zana.create_read_file_tool(state)
            @test tool.name == "read_file"

            # Read entire file
            result = tool.fn(Dict{String, Any}("file_path" => "test.txt"))
            @test haskey(result, "content")
            @test result["total_lines"] == 5
            @test contains(result["content"], "line1")
            @test contains(result["content"], "line5")

            # Read with offset and limit
            result = tool.fn(Dict{String, Any}("file_path" => "test.txt", "offset" => 2, "limit" => 2))
            @test result["lines_shown"] == "2-3"
            @test contains(result["content"], "line2")
            @test contains(result["content"], "line3")
            @test !contains(result["content"], "line1")

            # File not found
            result = tool.fn(Dict{String, Any}("file_path" => "nonexistent.txt"))
            @test haskey(result, "error")
        end

        @testset "write_file" begin
            tool = Zana.create_write_file_tool(state)
            @test tool.name == "write_file"

            # Write a new file
            result = tool.fn(Dict{String, Any}("file_path" => "new_file.txt", "content" => "hello world"))
            @test result["status"] == "ok"
            @test isfile(joinpath(test_dir, "new_file.txt"))
            @test read(joinpath(test_dir, "new_file.txt"), String) == "hello world"

            # Write with nested directories
            result = tool.fn(Dict{String, Any}("file_path" => "sub/dir/file.txt", "content" => "nested"))
            @test result["status"] == "ok"
            @test isfile(joinpath(test_dir, "sub", "dir", "file.txt"))
        end

        @testset "edit_file" begin
            tool = Zana.create_edit_file_tool(state)
            @test tool.name == "edit_file"

            # Create a file to edit
            edit_file = joinpath(test_dir, "edit_me.txt")
            write(edit_file, "foo bar baz\nhello world\n")

            # Successful edit
            result = tool.fn(Dict{String, Any}(
                "file_path" => "edit_me.txt",
                "old_string" => "hello world",
                "new_string" => "hello julia"
            ))
            @test result["status"] == "ok"
            @test contains(read(edit_file, String), "hello julia")

            # old_string not found
            result = tool.fn(Dict{String, Any}(
                "file_path" => "edit_me.txt",
                "old_string" => "does not exist",
                "new_string" => "replacement"
            ))
            @test haskey(result, "error")
            @test contains(result["error"], "not found")

            # Duplicate old_string
            write(edit_file, "aaa\naaa\n")
            result = tool.fn(Dict{String, Any}(
                "file_path" => "edit_me.txt",
                "old_string" => "aaa",
                "new_string" => "bbb"
            ))
            @test haskey(result, "error")
            @test contains(result["error"], "2 times")
        end

        @testset "run_bash" begin
            tool = Zana.create_run_bash_tool(state, 100_000)
            @test tool.name == "run_bash"

            # Simple command
            result = tool.fn(Dict{String, Any}("command" => "echo hello"))
            @test result["exit_code"] == 0
            @test strip(result["stdout"]) == "hello"

            # Command with error
            result = tool.fn(Dict{String, Any}("command" => "ls /nonexistent_dir_12345"))
            @test result["exit_code"] != 0

            # Check working directory (bash pwd returns POSIX paths on Windows,
            # so we only verify on Unix where paths match)
            if !Sys.iswindows()
                result = tool.fn(Dict{String, Any}("command" => "pwd"))
                @test strip(result["stdout"]) == test_dir
            end
        end

        @testset "glob_files" begin
            # Create some files for globbing
            write(joinpath(test_dir, "a.jl"), "")
            write(joinpath(test_dir, "b.jl"), "")
            mkpath(joinpath(test_dir, "src"))
            write(joinpath(test_dir, "src", "c.jl"), "")

            tool = Zana.create_glob_files_tool(state)
            @test tool.name == "glob_files"

            # Glob for .jl files
            result = tool.fn(Dict{String, Any}("pattern" => "**/*.jl"))
            @test result["total"] >= 3

            # Glob in subdirectory
            result = tool.fn(Dict{String, Any}("pattern" => "*.jl", "path" => "src"))
            @test result["total"] >= 1
        end

        @testset "list_directory" begin
            tool = Zana.create_list_directory_tool(state)
            @test tool.name == "list_directory"

            result = tool.fn(Dict{String, Any}())
            @test haskey(result, "entries")
            @test result["total"] > 0
            @test contains(result["entries"], "src/")  # directory should have / suffix

            # Invalid directory
            result = tool.fn(Dict{String, Any}("path" => "/nonexistent_dir_12345"))
            @test haskey(result, "error")
        end

        @testset "grep_code" begin
            # Create a file with known content
            write(joinpath(test_dir, "searchme.jl"), "function foo()\n    return 42\nend\n")

            tool = Zana.create_grep_code_tool(state, 100_000)
            @test tool.name == "grep_code"

            result = tool.fn(Dict{String, Any}("pattern" => "function foo", "path" => test_dir))
            @test contains(result["matches"], "function foo")

            # No matches
            result = tool.fn(Dict{String, Any}("pattern" => "zzznotfound123", "path" => test_dir))
            @test haskey(result, "note") || isempty(get(result, "matches", ""))
        end

        # Cleanup
        rm(test_dir; recursive=true, force=true)
    end

    @testset "Agent construction" begin
        config = ZanaConfig(
            ollama = OllamaConfig(model="test-model")
        )
        agent = ZanaAgent(config, "/tmp")
        @test agent.state.working_directory == "/tmp"
        @test length(agent.tools) == 7
        @test !isempty(agent.system_prompt)

        # Agent with Claude config
        claude_config = ZanaConfig(
            claude = ClaudeConfig(api_key="test-key", model="claude-sonnet-4-20250514")
        )
        claude_agent = ZanaAgent(claude_config, "/tmp")
        @test claude_agent.state.working_directory == "/tmp"
        @test length(claude_agent.tools) == 7
        @test contains(claude_agent.system_prompt, "claude-sonnet-4-20250514")
    end

    @testset "System prompt" begin
        prompt = Zana.build_system_prompt("/home/test", "test-model")
        @test contains(prompt, "Zana")
        @test contains(prompt, "/home/test")
        @test contains(prompt, "read_file")
        @test contains(prompt, "edit_file")
        @test contains(prompt, "Julia")
    end

    @testset "Path resolution" begin
        base_dir = joinpath("home", "user", "project")
        if !Sys.iswindows()
            base_dir = "/" * base_dir
        else
            base_dir = "C:\\" * base_dir
        end
        state = ZanaState(base_dir)
        @test Zana._resolve_path(state, "src/main.jl") == joinpath(base_dir, "src", "main.jl")
        @test Zana._resolve_path(state, joinpath("src", "main.jl")) == joinpath(base_dir, "src", "main.jl")
        @test isabspath(Zana._resolve_path(state, "../other/file.jl"))
    end

    @testset "Glob to regex" begin
        r = Zana._glob_to_regex("*.jl")
        @test occursin(r, "foo.jl")
        @test !occursin(r, "src/foo.jl")

        r = Zana._glob_to_regex("**/*.jl")
        @test occursin(r, "foo.jl")
        @test occursin(r, "src/foo.jl")
        @test occursin(r, "a/b/c.jl")
        @test !occursin(r, "foo.py")
    end

    @testset "Claude backend" begin
        @testset "ClaudeConfig defaults" begin
            cfg = ClaudeConfig(api_key="test-key")
            @test cfg.api_key == "test-key"
            @test cfg.model == "claude-sonnet-4-20250514"
            @test cfg.base_url == "https://api.anthropic.com"
            @test cfg.max_tokens == 8192
            @test cfg.temperature == 0.1
            @test cfg.api_version == "2023-06-01"
        end

        @testset "ZanaConfig with Claude" begin
            cfg = ZanaConfig(claude=ClaudeConfig(api_key="k"))
            @test !isnothing(cfg.claude)
            @test isnothing(cfg.llm)
            @test isnothing(cfg.ollama)
        end

        @testset "tools_to_claude_format" begin
            tools = Zana.Tool[
                Zana.Tool(
                    "read_file",
                    "Read a file",
                    Dict{String,Any}("type" => "object", "properties" => Dict("path" => Dict("type" => "string"))),
                    identity
                )
            ]
            result = Zana.tools_to_claude_format(tools)
            @test length(result) == 1
            @test result[1]["name"] == "read_file"
            @test result[1]["description"] == "Read a file"
            @test haskey(result[1], "input_schema")
            @test !haskey(result[1], "parameters")
            @test result[1]["input_schema"]["type"] == "object"
        end

        @testset "messages_to_claude_format" begin
            # System extraction
            msgs = Zana.Message[
                Zana.Message("system", "You are helpful"),
                Zana.Message("user", "Hello"),
            ]
            (sys, claude_msgs) = Zana.messages_to_claude_format(msgs)
            @test sys == "You are helpful"
            @test length(claude_msgs) == 1
            @test claude_msgs[1]["role"] == "user"
            @test claude_msgs[1]["content"] == "Hello"

            # No system or tool roles in output
            for m in claude_msgs
                @test m["role"] != "system"
                @test m["role"] != "tool"
            end

            # Tool call content blocks
            tc = Zana.ToolCall("tc-1", "read_file", Dict{String,Any}("path" => "a.jl"))
            msgs2 = Zana.Message[
                Zana.Message("assistant", "Let me read that", [tc], nothing),
            ]
            (_, claude_msgs2) = Zana.messages_to_claude_format(msgs2)
            @test length(claude_msgs2) == 1
            blocks = claude_msgs2[1]["content"]
            @test blocks[1]["type"] == "text"
            @test blocks[1]["text"] == "Let me read that"
            @test blocks[2]["type"] == "tool_use"
            @test blocks[2]["id"] == "tc-1"
            @test blocks[2]["name"] == "read_file"

            # Tool result conversion
            tool_msg = Zana.Message("tool", "{\"content\":\"file data\"}", nothing, "tc-1")
            msgs3 = Zana.Message[tool_msg]
            (_, claude_msgs3) = Zana.messages_to_claude_format(msgs3)
            @test length(claude_msgs3) == 1
            @test claude_msgs3[1]["role"] == "user"
            @test claude_msgs3[1]["content"][1]["type"] == "tool_result"
            @test claude_msgs3[1]["content"][1]["tool_use_id"] == "tc-1"

            # Consecutive tool results grouped into single user message
            tool_msg2 = Zana.Message("tool", "result2", nothing, "tc-2")
            msgs4 = Zana.Message[tool_msg, tool_msg2]
            (_, claude_msgs4) = Zana.messages_to_claude_format(msgs4)
            @test length(claude_msgs4) == 1
            @test length(claude_msgs4[1]["content"]) == 2
            @test claude_msgs4[1]["content"][1]["tool_use_id"] == "tc-1"
            @test claude_msgs4[1]["content"][2]["tool_use_id"] == "tc-2"
        end

        @testset "parse_claude_response" begin
            # Text-only response
            resp_text = Dict{String,Any}(
                "content" => [
                    Dict{String,Any}("type" => "text", "text" => "Hello there!")
                ],
                "usage" => Dict{String,Any}("input_tokens" => 10, "output_tokens" => 5)
            )
            msg = Zana.parse_claude_response(resp_text)
            @test msg.role == "assistant"
            @test msg.content == "Hello there!"
            @test isnothing(msg.tool_calls)

            # Tool use response
            resp_tool = Dict{String,Any}(
                "content" => [
                    Dict{String,Any}("type" => "text", "text" => "Reading file"),
                    Dict{String,Any}(
                        "type" => "tool_use",
                        "id" => "tu-1",
                        "name" => "read_file",
                        "input" => Dict{String,Any}("file_path" => "test.jl")
                    )
                ]
            )
            msg2 = Zana.parse_claude_response(resp_tool)
            @test msg2.content == "Reading file"
            @test length(msg2.tool_calls) == 1
            @test msg2.tool_calls[1].id == "tu-1"
            @test msg2.tool_calls[1].name == "read_file"
            @test msg2.tool_calls[1].arguments["file_path"] == "test.jl"

            # Tool-only response (no text)
            resp_tool_only = Dict{String,Any}(
                "content" => [
                    Dict{String,Any}(
                        "type" => "tool_use",
                        "id" => "tu-2",
                        "name" => "run_bash",
                        "input" => Dict{String,Any}("command" => "ls")
                    )
                ]
            )
            msg3 = Zana.parse_claude_response(resp_tool_only)
            @test isnothing(msg3.content)
            @test length(msg3.tool_calls) == 1
            @test msg3.tool_calls[1].name == "run_bash"
        end

        @testset "_extract_usage Claude" begin
            claude_cfg = ZanaConfig(claude=ClaudeConfig(api_key="k"))
            agent = ZanaAgent(claude_cfg, "/tmp")
            response = Dict{String,Any}(
                "usage" => Dict{String,Any}("input_tokens" => 100, "output_tokens" => 42)
            )
            (in_tok, out_tok) = Zana._extract_usage(agent, response)
            @test in_tok == 100
            @test out_tok == 42
        end
    end

    @testset "Truncate output" begin
        @test Zana._truncate_output("hello", 100) == "hello"
        result = Zana._truncate_output("hello world", 5)
        @test length(result) > 5  # includes truncation notice
        @test contains(result, "truncated")
    end

end
