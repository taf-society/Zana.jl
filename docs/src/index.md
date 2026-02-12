# Zana.jl

![Zana.jl logo](assets/logo.svg)

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://taf-society.github.io/Zana.jl/stable/) [![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://taf-society.github.io/Zana.jl/dev/) [![Build Status](https://github.com/taf-society/Zana.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/taf-society/Zana.jl/actions/workflows/CI.yml?query=branch%3Amain) [![Coverage](https://codecov.io/gh/taf-society/Zana.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/taf-society/Zana.jl)

**Zana** is a REPL-based AI coding copilot for Julia. It connects to LLMs (OpenAI, Anthropic Claude, Ollama, or any OpenAI-compatible API) and gives them tools to read, write, edit, and search your codebase — all from an interactive terminal session.

Zana — Kurdish for "wise/scholar", embodies the pursuit of intelligent assistance through language models. Like a knowledgeable companion at your side, Zana brings the reasoning power of modern AI directly into your Julia development workflow.

> This site documents the development version. After your first tagged release, see **stable** docs for the latest release.

---

## About TAFS

**TAFS (Time Series Analysis and Forecasting Society)** is a non-profit association ("Verein") in Vienna, Austria. It connects academics, experts, practitioners, and students focused on time-series, forecasting, and decision science. Contributions remain fully open source.
Learn more at [taf-society.org](https://taf-society.org/).

---

## Installation

Zana is under active development. For the latest dev version:

```julia
using Pkg
Pkg.add(url="https://github.com/taf-society/Zana.jl")
```

For local development:

```julia
] dev /path/to/Zana.jl
```

---

## REPL Interface (Primary Usage)

Zana provides an interactive REPL that gives an LLM full access to your codebase through 7 built-in tools. This is the **recommended approach** for most users.

### Quick Example: Ollama

```julia
using Zana

zana(ollama=true, model="qwen3")
```

### Quick Example: Anthropic Claude

```julia
using Zana

# Reads ANTHROPIC_API_KEY from environment
zana(claude=true)
```

### Quick Example: OpenAI

```julia
using Zana

# Reads OPENAI_API_KEY from environment
zana()

# Or pass the key directly
zana(api_key="sk-...")
```

### Quick Example: Any OpenAI-Compatible API

```julia
using Zana

zana(api_key="your-key", base_url="https://api.example.com/v1", model="your-model")
```

Once inside the REPL, the LLM can autonomously read files, search code, run commands, and make edits to help you with any coding task.

!!! tip "Available Commands"
    Type `/help` inside the Zana REPL to see all available commands. Use `/exit` to quit.

---

## Programmatic Usage (Agent API)

For integration into scripts or custom workflows, use `ZanaAgent` and `process_turn` directly:

```julia
using Zana

config = ZanaConfig(
    ollama = OllamaConfig(model="qwen3")
)

agent = ZanaAgent(config, pwd())
result = process_turn(agent, "List all Julia files in this project")

# Access the response
println(result.response)

# Inspect tool executions
for exec in result.tool_executions
    println("  $(exec.tool_name) ($(exec.duration_ms)ms)")
end
```

---

## Available Tools

Zana equips the LLM with 7 coding tools:

| Tool | Description | Use Case |
|------|-------------|----------|
| **`read_file`** | Read file contents with line numbers | Inspecting code, understanding structure |
| **`write_file`** | Create or overwrite files | Generating new modules, configs, scripts |
| **`edit_file`** | Exact string replacement | Targeted code modifications |
| **`run_bash`** | Execute shell commands with timeout | Running tests, git operations, builds |
| **`glob_files`** | Find files by glob pattern | Discovering project structure |
| **`grep_code`** | Regex search across files | Finding usages, patterns, definitions |
| **`list_directory`** | List directory contents with sizes | Exploring directory layout |

For detailed documentation on each tool, see the [Tools Guide](tools.md).

---

## Key Features

- **Multiple LLM Backends** — OpenAI, Anthropic Claude, Ollama, or any OpenAI-compatible API
- **7 Built-in Tools** — Read, write, edit, search, and run commands
- **Interactive REPL** — Conversational coding with full context
- **Programmatic API** — Use `ZanaAgent` directly in scripts
- **Minimal Dependencies** — Only **HTTP**, **JSON3**, **UUIDs**
- **Multi-line Input** — Backslash continuation for complex prompts
- **Token Tracking** — Monitor LLM usage across the session

---

## License

MIT License.

---

## What's next

- **[Quick Start](quickstart.md)** — Get started quickly with Ollama or OpenAI
- **User Guide** pages:
  - [REPL Interface](repl.md) — Commands, multi-line input, and session management
  - [Tools](tools.md) — Detailed documentation for all 7 coding tools
  - [Configuration](configuration.md) — `ZanaConfig`, `LLMConfig`, `OllamaConfig`, `ClaudeConfig`
  - [Ollama Integration](ollama.md) — Local model setup, utilities, and tips
  - [Claude Integration](claude.md) — Anthropic Claude setup and usage
- **[API Reference](api.md)** — Complete API documentation
