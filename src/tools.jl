



"""
    _resolve_path(state, path)

Resolve a path relative to the working directory. Absolute paths pass through.
"""
function _resolve_path(state::ZanaState, path::String)
    if isabspath(path)
        return path
    end
    return normpath(joinpath(state.working_directory, path))
end

"""
    _truncate_output(text, max_chars)

Truncate output to max_chars, adding a notice if truncated.
"""
function _truncate_output(text::String, max_chars::Int)
    if length(text) <= max_chars
        return text
    end
    return text[1:max_chars] * "\n\n[Output truncated at $max_chars characters]"
end




function create_read_file_tool(state::ZanaState)
    Tool(
        "read_file",
        "Read the contents of a file with line numbers. Supports offset and limit for large files. Default limit is 2000 lines.",
        Dict{String, Any}(
            "type" => "object",
            "properties" => Dict{String, Any}(
                "file_path" => Dict{String, Any}(
                    "type" => "string",
                    "description" => "Path to the file to read (absolute or relative to working directory)"
                ),
                "offset" => Dict{String, Any}(
                    "type" => "integer",
                    "description" => "Line number to start reading from (1-based, default: 1)"
                ),
                "limit" => Dict{String, Any}(
                    "type" => "integer",
                    "description" => "Maximum number of lines to read (default: 2000)"
                )
            ),
            "required" => ["file_path"]
        ),
        function(args)
            try
                path = _resolve_path(state, args["file_path"])
                offset = get(args, "offset", 1)
                offset = offset isa AbstractString ? parse(Int, offset) : Int(offset)
                limit = get(args, "limit", 2000)
                limit = limit isa AbstractString ? parse(Int, limit) : Int(limit)

                if !isfile(path)
                    return Dict("error" => "File not found: $path")
                end

                lines = readlines(path)
                total = length(lines)
                start_line = clamp(offset, 1, max(total, 1))
                end_line = clamp(start_line + limit - 1, start_line, total)

                numbered = String[]
                for i in start_line:end_line
                    line = lines[i]

                    if length(line) > 2000
                        line = line[1:2000] * "..."
                    end
                    push!(numbered, "$(lpad(i, ndigits(end_line)))\t$(line)")
                end

                content = join(numbered, "\n")
                return Dict("content" => content, "total_lines" => total,
                           "lines_shown" => "$(start_line)-$(end_line)")
            catch e
                return Dict("error" => "Failed to read file: $(sprint(showerror, e))")
            end
        end
    )
end




function create_write_file_tool(state::ZanaState)
    Tool(
        "write_file",
        "Create or overwrite a file with the given content. Parent directories are created automatically.",
        Dict{String, Any}(
            "type" => "object",
            "properties" => Dict{String, Any}(
                "file_path" => Dict{String, Any}(
                    "type" => "string",
                    "description" => "Path to the file to write (absolute or relative to working directory)"
                ),
                "content" => Dict{String, Any}(
                    "type" => "string",
                    "description" => "Content to write to the file"
                )
            ),
            "required" => ["file_path", "content"]
        ),
        function(args)
            try
                path = _resolve_path(state, args["file_path"])
                content = args["content"]

                mkpath(dirname(path))

                write(path, content)
                return Dict("status" => "ok", "path" => path, "bytes_written" => filesize(path))
            catch e
                return Dict("error" => "Failed to write file: $(sprint(showerror, e))")
            end
        end
    )
end




function create_edit_file_tool(state::ZanaState)
    Tool(
        "edit_file",
        "Perform an exact string replacement in a file. The old_string must appear exactly once in the file. Use this for surgical edits to existing files.",
        Dict{String, Any}(
            "type" => "object",
            "properties" => Dict{String, Any}(
                "file_path" => Dict{String, Any}(
                    "type" => "string",
                    "description" => "Path to the file to edit"
                ),
                "old_string" => Dict{String, Any}(
                    "type" => "string",
                    "description" => "Exact string to find and replace (must be unique in the file)"
                ),
                "new_string" => Dict{String, Any}(
                    "type" => "string",
                    "description" => "Replacement string"
                )
            ),
            "required" => ["file_path", "old_string", "new_string"]
        ),
        function(args)
            try
                path = _resolve_path(state, args["file_path"])
                old_str = args["old_string"]
                new_str = args["new_string"]

                if !isfile(path)
                    return Dict("error" => "File not found: $path")
                end

                content = read(path, String)

                n_occurrences = 0
                search_from = 1
                while true
                    idx = findnext(old_str, content, search_from)
                    if isnothing(idx)
                        break
                    end
                    n_occurrences += 1
                    search_from = first(idx) + 1
                end

                if n_occurrences == 0
                    return Dict("error" => "old_string not found in file")
                elseif n_occurrences > 1
                    return Dict("error" => "old_string found $n_occurrences times (must be unique). Provide more context to make it unique.")
                end

                new_content = replace(content, old_str => new_str; count=1)
                write(path, new_content)
                return Dict("status" => "ok", "path" => path)
            catch e
                return Dict("error" => "Failed to edit file: $(sprint(showerror, e))")
            end
        end
    )
end




function create_run_bash_tool(state::ZanaState, max_output_chars::Int)
    Tool(
        "run_bash",
        "Execute a bash command in the working directory. Returns stdout and stderr. Use for git, build tools, running tests, etc.",
        Dict{String, Any}(
            "type" => "object",
            "properties" => Dict{String, Any}(
                "command" => Dict{String, Any}(
                    "type" => "string",
                    "description" => "Bash command to execute"
                ),
                "timeout" => Dict{String, Any}(
                    "type" => "integer",
                    "description" => "Timeout in seconds (default: 120)"
                )
            ),
            "required" => ["command"]
        ),
        function(args)
            try
                cmd_str = args["command"]
                timeout_secs = get(args, "timeout", 120)
                timeout_secs = timeout_secs isa AbstractString ? parse(Int, timeout_secs) : Int(timeout_secs)

                out = IOBuffer()
                err = IOBuffer()

                cmd = ignorestatus(Cmd(`bash -c $cmd_str`; dir=state.working_directory))
                proc = run(pipeline(cmd, stdout=out, stderr=err); wait=false)

                timed_out = false
                deadline = time() + timeout_secs
                while process_running(proc)
                    if time() > deadline
                        timed_out = true
                        kill(proc)
                        break
                    end
                    sleep(0.05)
                end
                wait(proc)

                stdout_str = String(take!(out))
                stderr_str = String(take!(err))

                stdout_str = _truncate_output(stdout_str, max_output_chars)
                stderr_str = _truncate_output(stderr_str, max_output_chars)

                result = Dict{String, Any}(
                    "exit_code" => proc.exitcode,
                    "stdout" => stdout_str,
                    "stderr" => stderr_str
                )

                if timed_out
                    result["timed_out"] = true
                end

                return result
            catch e
                return Dict("error" => "Failed to execute command: $(sprint(showerror, e))")
            end
        end
    )
end




function create_glob_files_tool(state::ZanaState)
    Tool(
        "glob_files",
        "Find files matching a glob pattern. Supports patterns like '**/*.jl', 'src/*.jl', '*.toml'. Results sorted by modification time (newest first).",
        Dict{String, Any}(
            "type" => "object",
            "properties" => Dict{String, Any}(
                "pattern" => Dict{String, Any}(
                    "type" => "string",
                    "description" => "Glob pattern to match (e.g., '**/*.jl', 'src/**/*.ts')"
                ),
                "path" => Dict{String, Any}(
                    "type" => "string",
                    "description" => "Directory to search in (default: working directory)"
                )
            ),
            "required" => ["pattern"]
        ),
        function(args)
            try
                pattern = args["pattern"]
                search_dir = haskey(args, "path") ? _resolve_path(state, args["path"]) : state.working_directory

                if !isdir(search_dir)
                    return Dict("error" => "Directory not found: $search_dir")
                end

                regex = _glob_to_regex(pattern)

                matches = String[]
                for (root, dirs, files) in walkdir(search_dir)

                    filter!(d -> !startswith(d, "."), dirs)

                    for file in files
                        full_path = joinpath(root, file)
                        rel_path = relpath(full_path, search_dir)

                        if occursin(regex, rel_path)
                            push!(matches, rel_path)
                        end
                    end
                end

                sort!(matches; by = f -> mtime(joinpath(search_dir, f)), rev=true)

                if length(matches) > 500
                    matches = matches[1:500]
                    return Dict("files" => matches, "total" => length(matches),
                               "note" => "Results truncated to 500 files")
                end

                return Dict("files" => matches, "total" => length(matches))
            catch e
                return Dict("error" => "Failed to glob files: $(sprint(showerror, e))")
            end
        end
    )
end

"""
    _glob_to_regex(pattern)

Convert a glob pattern to a Regex.
Supports: `*` (any non-/ chars), `**` (any chars including /), `?` (single char).
"""
function _glob_to_regex(pattern::String)
    regex_str = "^"
    i = 1
    while i <= length(pattern)
        c = pattern[i]
        if c == '*'
            if i < length(pattern) && pattern[i+1] == '*'

                if i + 2 <= length(pattern) && pattern[i+2] == '/'
                    regex_str *= "(.+/)?"
                    i += 3
                    continue
                else
                    regex_str *= ".*"
                    i += 2
                    continue
                end
            else
                regex_str *= "[^/]*"
            end
        elseif c == '?'
            regex_str *= "[^/]"
        elseif c == '.'
            regex_str *= "\\."
        elseif c == '/'
            regex_str *= "/"
        else
            regex_str *= string(c)
        end
        i += 1
    end
    regex_str *= "\$"
    return Regex(regex_str)
end




function create_grep_code_tool(state::ZanaState, max_output_chars::Int)
    Tool(
        "grep_code",
        "Search for a regex pattern in files. Returns matching lines with file paths and line numbers. Supports file type filtering with glob patterns.",
        Dict{String, Any}(
            "type" => "object",
            "properties" => Dict{String, Any}(
                "pattern" => Dict{String, Any}(
                    "type" => "string",
                    "description" => "Regex pattern to search for"
                ),
                "path" => Dict{String, Any}(
                    "type" => "string",
                    "description" => "File or directory to search in (default: working directory)"
                ),
                "glob" => Dict{String, Any}(
                    "type" => "string",
                    "description" => "Glob filter for files (e.g., '*.jl', '*.py')"
                ),
                "context" => Dict{String, Any}(
                    "type" => "integer",
                    "description" => "Number of context lines before and after each match (default: 0)"
                )
            ),
            "required" => ["pattern"]
        ),
        function(args)
            try
                pattern = args["pattern"]
                search_path = haskey(args, "path") ? _resolve_path(state, args["path"]) : state.working_directory
                ctx = get(args, "context", 0)
                ctx = ctx isa AbstractString ? parse(Int, ctx) : Int(ctx)

                cmd_parts = ["grep", "-rn"]

                if ctx > 0
                    push!(cmd_parts, "-C", string(ctx))
                end

                if haskey(args, "glob")
                    push!(cmd_parts, "--include=$(args["glob"])")
                end

                push!(cmd_parts, pattern, search_path)

                out = IOBuffer()
                err = IOBuffer()

                proc = run(pipeline(Cmd(Cmd(cmd_parts)); stdout=out, stderr=err); wait=true)

                output = String(take!(out))
                output = _truncate_output(output, max_output_chars)

                if startswith(search_path, state.working_directory)
                    output = replace(output, state.working_directory * "/" => "")
                end

                return Dict("matches" => output, "exit_code" => proc.exitcode)
            catch e
                err_str = sprint(showerror, e)

                if contains(err_str, "failed process") || contains(err_str, "exit code 1")
                    return Dict("matches" => "", "note" => "No matches found")
                end
                return Dict("error" => "Failed to grep: $err_str")
            end
        end
    )
end




function create_list_directory_tool(state::ZanaState)
    Tool(
        "list_directory",
        "List the contents of a directory. Shows directories with '/' suffix and files with sizes.",
        Dict{String, Any}(
            "type" => "object",
            "properties" => Dict{String, Any}(
                "path" => Dict{String, Any}(
                    "type" => "string",
                    "description" => "Directory to list (default: working directory)"
                )
            ),
            "required" => []
        ),
        function(args)
            try
                dir = haskey(args, "path") ? _resolve_path(state, args["path"]) : state.working_directory

                if !isdir(dir)
                    return Dict("error" => "Not a directory: $dir")
                end

                entries = String[]
                for name in sort(readdir(dir))
                    full = joinpath(dir, name)
                    if isdir(full)
                        push!(entries, "$name/")
                    else
                        sz = filesize(full)
                        size_str = if sz < 1024
                            "$(sz) B"
                        elseif sz < 1024^2
                            "$(round(sz / 1024; digits=1)) KB"
                        else
                            "$(round(sz / 1024^2; digits=1)) MB"
                        end
                        push!(entries, "$name  ($size_str)")
                    end
                end

                return Dict("entries" => join(entries, "\n"), "total" => length(entries))
            catch e
                return Dict("error" => "Failed to list directory: $(sprint(showerror, e))")
            end
        end
    )
end
