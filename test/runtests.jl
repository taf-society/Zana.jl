using Test
using Bilge

@testset "Bilge.jl" begin

    @testset "Types" begin
        @testset "Message" begin
            msg = Bilge.Message("user", "hello")
            @test msg.role == "user"
            @test msg.content == "hello"
            @test isnothing(msg.tool_calls)
            @test isnothing(msg.tool_call_id)
        end

        @testset "ToolCall" begin
            tc = Bilge.ToolCall("id-1", "read_file", Dict{String, Any}("file_path" => "test.jl"))
            @test tc.id == "id-1"
            @test tc.name == "read_file"
            @test tc.arguments["file_path"] == "test.jl"
        end

        @testset "BilgeConfig" begin
            cfg = BilgeConfig()
            @test isnothing(cfg.llm)
            @test isnothing(cfg.ollama)
            @test cfg.max_tool_rounds == 50
            @test cfg.max_output_chars == 100_000
        end

        @testset "BilgeState" begin
            state = BilgeState("/tmp")
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
        state = BilgeState(test_dir)

        @testset "read_file" begin
            # Create a test file
            test_file = joinpath(test_dir, "test.txt")
            write(test_file, "line1\nline2\nline3\nline4\nline5\n")

            tool = Bilge.create_read_file_tool(state)
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
            tool = Bilge.create_write_file_tool(state)
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
            tool = Bilge.create_edit_file_tool(state)
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
            tool = Bilge.create_run_bash_tool(state, 100_000)
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

            tool = Bilge.create_glob_files_tool(state)
            @test tool.name == "glob_files"

            # Glob for .jl files
            result = tool.fn(Dict{String, Any}("pattern" => "**/*.jl"))
            @test result["total"] >= 3

            # Glob in subdirectory
            result = tool.fn(Dict{String, Any}("pattern" => "*.jl", "path" => "src"))
            @test result["total"] >= 1
        end

        @testset "list_directory" begin
            tool = Bilge.create_list_directory_tool(state)
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

            tool = Bilge.create_grep_code_tool(state, 100_000)
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
        config = BilgeConfig(
            ollama = OllamaConfig(model="test-model")
        )
        agent = BilgeAgent(config, "/tmp")
        @test agent.state.working_directory == "/tmp"
        @test length(agent.tools) == 7
        @test !isempty(agent.system_prompt)
    end

    @testset "System prompt" begin
        prompt = Bilge.build_system_prompt("/home/test")
        @test contains(prompt, "Bilge")
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
        state = BilgeState(base_dir)
        @test Bilge._resolve_path(state, "src/main.jl") == joinpath(base_dir, "src", "main.jl")
        @test Bilge._resolve_path(state, joinpath("src", "main.jl")) == joinpath(base_dir, "src", "main.jl")
        @test isabspath(Bilge._resolve_path(state, "../other/file.jl"))
    end

    @testset "Glob to regex" begin
        r = Bilge._glob_to_regex("*.jl")
        @test occursin(r, "foo.jl")
        @test !occursin(r, "src/foo.jl")

        r = Bilge._glob_to_regex("**/*.jl")
        @test occursin(r, "foo.jl")
        @test occursin(r, "src/foo.jl")
        @test occursin(r, "a/b/c.jl")
        @test !occursin(r, "foo.py")
    end

    @testset "Truncate output" begin
        @test Bilge._truncate_output("hello", 100) == "hello"
        result = Bilge._truncate_output("hello world", 5)
        @test length(result) > 5  # includes truncation notice
        @test contains(result, "truncated")
    end

end
