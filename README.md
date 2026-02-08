<div align="center">
<img src="docs/src/assets/logo.png"/>
</div>

# Bilge.jl

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://akai01.github.io/Bilge.jl/stable/) [![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://akai01.github.io/Bilge.jl/dev/) [![Build Status](https://github.com/akai01/Bilge.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/akai01/Bilge.jl/actions/workflows/CI.yml?query=branch%3Amain) [![Coverage](https://codecov.io/gh/akai01/Bilge.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/akai01/Bilge.jl)

## About

**Bilge** is a REPL-based AI coding copilot for Julia. It connects to LLMs (OpenAI, Ollama, or any OpenAI-compatible API) and gives them tools to read, write, edit, and search your codebase — all from an interactive terminal session.

Bilge — Turkish for "wise", embodies the pursuit of intelligent assistance through language models. Like a knowledgeable companion at your side, Bilge brings the reasoning power of modern AI directly into your Julia development workflow.

This package is currently under development and will be part of the **TAFS Open Source Ecosystem**.

## About TAFS

**TAFS (Time Series Analysis and Forecasting Society)** is a non-profit association registered as a **"Verein"** in Vienna, Austria. The organization connects a global audience of academics, experts, practitioners, and students to engage, share, learn, and innovate in the fields of data science and artificial intelligence, with a particular focus on time-series analysis, forecasting, and decision science. [TAFS](https://taf-society.org/)

TAFS's mission includes:

-   **Connecting**: Hosting events and discussion groups to establish connections and build a community of like-minded individuals.
-   **Learning**: Providing a platform to learn about the latest research, real-world problems, and applications.
-   **Sharing**: Inviting experts, academics, practitioners, and others to present and discuss problems, research, and solutions.
-   **Innovating**: Supporting the transfer of research into solutions and helping to drive innovations.

As a registered non-profit association under Austrian law, TAFS ensures that all contributions remain fully open source and cannot be privatized or commercialized. [TAFS](https://taf-society.org/)

## License

The Bilge package is licensed under the **MIT License**, allowing for open-source distribution and collaboration.

## Installation

Bilge is still in development. Once it is officially released, you will be able to install it using Julia's package manager.

For the latest development version, you can install directly from GitHub:

```julia
using Pkg
Pkg.add(url="https://github.com/akai01/Bilge.jl")
```

For local development:

```julia
] dev /path/to/Bilge.jl
```

## Quick Start

### With Ollama (Local Models)

```julia
using Bilge

# Start with a local Ollama model
bilge(ollama=true, model="qwen3")
```

### With OpenAI

```julia
using Bilge

# Reads OPENAI_API_KEY from environment
bilge()

# Or pass the key directly
bilge(api_key="sk-...")
```

### With Any OpenAI-Compatible API

```julia
using Bilge

bilge(api_key="your-key", base_url="https://api.example.com/v1", model="your-model")
```

---

## REPL Interface (Primary Usage)

Once inside the Bilge REPL, you have a full interactive coding assistant at your disposal. The assistant can read, write, edit, and search your project using 7 built-in tools.

### REPL Commands

| Command | Description |
|---------|-------------|
| `/help` | Show available commands |
| `/exit`, `/quit` | Exit Bilge |
| `/clear` | Clear conversation history |
| `/history` | Show conversation history |
| `/tokens` | Show cumulative token usage |
| `/cd PATH` | Change working directory |

### Multi-Line Input

Use a trailing `\` for multi-line input:

```
bilge> Write a function that \
  ...> parses CSV files and \
  ...> returns a DataFrame.
```

---

## Available Tools

Bilge gives the LLM 7 tools to work with your codebase:

| Tool | Description | Use Case |
|------|-------------|----------|
| `read_file` | Read file contents with line numbers | Inspecting code, understanding structure |
| `write_file` | Create or overwrite files | Generating new modules, configs, scripts |
| `edit_file` | Exact string replacement | Targeted code modifications |
| `run_bash` | Execute shell commands with timeout | Running tests, git operations, builds |
| `glob_files` | Find files by glob pattern | Discovering project structure |
| `grep_code` | Regex search across files | Finding usages, patterns, definitions |
| `list_directory` | List directory contents with sizes | Exploring directory layout |

---

## Programmatic Usage (Agent API)

You can use `BilgeAgent` and `process_turn` directly without the REPL:

```julia
using Bilge

config = BilgeConfig(
    ollama = OllamaConfig(model="qwen3")
)

agent = BilgeAgent(config, pwd())
result = process_turn(agent, "List all Julia files in this project")

# Access the response
println(result.response)

# Inspect tool executions
for exec in result.tool_executions
    println("  $(exec.tool_name) ($(exec.duration_ms)ms)")
end
```

### `TurnResult`

| Field | Type | Description |
|-------|------|-------------|
| `response` | `String` | The LLM's final text response |
| `tool_executions` | `Vector{ToolExecution}` | Record of each tool call (name, args, result, duration) |
| `input_tokens` | `Int` | Tokens consumed this turn |
| `output_tokens` | `Int` | Tokens generated this turn |

---

## Configuration

### `BilgeConfig`

```julia
BilgeConfig(
    llm = LLMConfig(...),          # OpenAI-compatible backend
    ollama = OllamaConfig(...),    # Ollama backend (set one or the other)
    max_tool_rounds = 50,          # Max tool-call rounds per turn
    max_output_chars = 100_000,    # Truncate tool output beyond this
)
```

### `LLMConfig`

```julia
LLMConfig(
    api_key = "sk-...",
    model = "gpt-4o",
    base_url = "https://api.openai.com/v1",
    max_tokens = 4096,
    temperature = 0.1,
)
```

### `OllamaConfig`

```julia
OllamaConfig(
    model = "qwen3",
    host = "http://localhost:11434",
    max_tokens = 4096,
    temperature = 0.1,
    use_openai_compat = false,     # Use /v1 endpoint instead of /api/chat
)
```

---

## Ollama Utilities

```julia
using Bilge

# Check if Ollama is running
check_ollama_connection()

# List available models
list_ollama_models()
```

---

## Dependencies

Minimal: **HTTP**, **JSON3**, **UUIDs** only.

---

## License

MIT License.
