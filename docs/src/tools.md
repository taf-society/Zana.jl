# Tools

Bilge equips the LLM with 7 coding tools for interacting with your codebase. The LLM autonomously decides which tools to use based on your request.

---

## Overview

| Tool | Description | Best For |
|------|-------------|----------|
| **`read_file`** | Read file contents with line numbers | Inspecting code, understanding structure |
| **`write_file`** | Create or overwrite files | Generating new modules, configs, scripts |
| **`edit_file`** | Exact string replacement | Targeted code modifications |
| **`run_bash`** | Execute shell commands | Running tests, git operations, builds |
| **`glob_files`** | Find files by glob pattern | Discovering project structure |
| **`grep_code`** | Regex search across files | Finding usages, patterns, definitions |
| **`list_directory`** | List directory contents | Exploring directory layout |

---

## `read_file`

Read file contents with line numbers and optional offset/limit.

### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `file_path` | `String` | Yes | — | Absolute or relative path to the file |
| `offset` | `Int` | No | `1` | Starting line number |
| `limit` | `Int` | No | `2000` | Maximum number of lines to read |

### Behavior

- Returns file contents with line numbers (e.g., `  1│ module Bilge`)
- Lines longer than 2000 characters are truncated with a notice
- Returns total line count and lines shown
- Handles missing files with an error message

### Example Response

```json
{
  "content": "  1│ module Bilge\n  2│ \n  3│ using HTTP\n...",
  "total_lines": 37,
  "lines_shown": 37
}
```

---

## `write_file`

Create or overwrite a file. Parent directories are created automatically.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `file_path` | `String` | Yes | Absolute or relative path |
| `content` | `String` | Yes | File content to write |

### Behavior

- Creates the file and any missing parent directories
- Overwrites existing files without warning
- Returns the number of bytes written

### Example Response

```json
{
  "status": "ok",
  "path": "/home/user/project/src/new_file.jl",
  "bytes_written": 256
}
```

---

## `edit_file`

Perform exact string replacement in a file. The target string must appear exactly once.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `file_path` | `String` | Yes | Path to the file |
| `old_string` | `String` | Yes | Exact string to find (must be unique) |
| `new_string` | `String` | Yes | Replacement string |

### Behavior

- Reads the file and searches for `old_string`
- **Fails** if the string is not found or appears more than once
- Writes the modified content back to the file
- Returns the file path on success

!!! note "Uniqueness Requirement"
    The `old_string` must appear exactly once in the file. If it appears multiple times, the tool returns an error asking the LLM to provide a larger, unique context string. This prevents accidental multi-edits.

### Example Response

```json
{
  "status": "ok",
  "path": "/home/user/project/src/agent.jl"
}
```

---

## `run_bash`

Execute a shell command with a configurable timeout.

### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `command` | `String` | Yes | — | Shell command to execute |
| `timeout_seconds` | `Int` | No | `120` | Maximum execution time in seconds |

### Behavior

- Runs the command in the agent's working directory
- Captures stdout and stderr separately
- Enforces a timeout (default: 120 seconds)
- Returns exit code, output, and timeout status

### Example Response

```json
{
  "exit_code": 0,
  "stdout": "Test Summary...\n  All tests passed!",
  "stderr": "",
  "timed_out": false
}
```

---

## `glob_files`

Find files matching a glob pattern.

### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `pattern` | `String` | Yes | — | Glob pattern (e.g., `**/*.jl`, `src/*.toml`) |
| `path` | `String` | No | Working dir | Directory to search in |

### Behavior

- Supports `*` (any characters in filename), `**` (recursive directory), and `?` (single character)
- Results sorted by modification time (newest first)
- Limited to 500 results
- Returns file paths relative to the search directory

### Supported Patterns

| Pattern | Matches |
|---------|---------|
| `*.jl` | All `.jl` files in current directory |
| `**/*.jl` | All `.jl` files recursively |
| `src/**/*.jl` | All `.jl` files under `src/` |
| `test/test_*.jl` | Test files matching prefix |
| `*.{jl,toml}` | Not supported — use separate calls |

### Example Response

```json
{
  "files": ["src/agent.jl", "src/tools.jl", "src/repl.jl"],
  "total": 3
}
```

---

## `grep_code`

Search file contents with regex patterns.

### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `pattern` | `String` | Yes | — | Regex pattern to search for |
| `path` | `String` | No | Working dir | Directory to search in |
| `glob` | `String` | No | `""` | Filter files by glob pattern |
| `context_lines` | `Int` | No | `0` | Lines of context before and after matches |

### Behavior

- Uses `grep -rn` under the hood with regex support
- Can filter files by glob pattern (e.g., only search `*.jl` files)
- Returns matching lines with file paths and line numbers
- Supports context lines for surrounding code

### Example Response

```json
{
  "matches": "src/agent.jl:115:function process_turn(agent::BilgeAgent, user_input::AbstractString)\nsrc/repl.jl:121:            result = process_turn(agent, input)",
  "exit_code": 0
}
```

---

## `list_directory`

List the contents of a directory with file sizes.

### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `path` | `String` | No | Working dir | Directory to list |

### Behavior

- Shows directories with a `/` suffix
- Shows files with human-readable sizes
- Entries sorted alphabetically
- Returns total entry count

### Example Response

```json
{
  "entries": [
    "docs/                      (dir)",
    "src/                       (dir)",
    "test/                      (dir)",
    "Project.toml               378 bytes",
    "README.md                  3551 bytes"
  ],
  "total": 5
}
```

---

## Tool Limits and Safety

!!! info "Output Truncation"
    Tool output is truncated at `max_output_chars` (default: 100,000 characters) to prevent overwhelming the LLM's context window. A notice is appended when truncation occurs.

!!! info "Bash Timeout"
    Shell commands are killed after the timeout (default: 120 seconds) to prevent runaway processes.

!!! info "Glob Limit"
    File glob results are capped at 500 entries to prevent excessive output.

!!! info "Line Truncation"
    Lines longer than 2000 characters are truncated in `read_file` output.
