# REPL Interface

The Bilge REPL is the primary way to interact with the coding copilot. It provides an interactive terminal session where you can ask the LLM to read, write, edit, and search your codebase.

---

## Starting the REPL

### With Ollama (Local Models)

```julia
using Bilge

bilge(ollama=true, model="qwen3")
```

### With OpenAI

```julia
using Bilge

bilge()  # Reads OPENAI_API_KEY from environment
```

### With Custom API

```julia
using Bilge

bilge(api_key="your-key", base_url="https://api.example.com/v1", model="your-model")
```

### Full Parameter List

```julia
bilge(;
    api_key = nothing,             # OpenAI API key (or ENV["OPENAI_API_KEY"])
    model = nothing,               # Model name (default: "gpt-4o" or "llama3.1")
    base_url = "https://api.openai.com/v1",  # API base URL
    ollama = false,                # Use Ollama backend
    host = "http://localhost:11434",  # Ollama host
    use_openai_compat = false,     # Use Ollama's OpenAI-compatible endpoint
    working_dir = pwd()            # Working directory for tools
)
```

---

## REPL Commands

All commands start with `/`:

| Command | Description |
|---------|-------------|
| `/help` | Show available commands |
| `/exit`, `/quit` | Exit Bilge |
| `/clear` | Clear conversation history and start fresh |
| `/history` | Show a summary of the conversation |
| `/tokens` | Show cumulative token usage (input and output) |
| `/cd PATH` | Change the working directory for all tools |

### `/clear`

Resets the conversation history and turn count. The LLM will have no memory of previous exchanges. Useful when switching topics or starting a new task.

### `/history`

Displays a condensed summary of the conversation:
- **User messages** — Shows first 80 characters of each message
- **Assistant messages** — Shows tool calls or text preview
- **Tool results** — Omitted for brevity

### `/tokens`

Shows cumulative token usage across all turns:
```
  Total tokens: 15420 in / 3280 out
  Turns: 5
```

### `/cd PATH`

Changes the working directory for all tools. The system prompt and tool paths are updated automatically:
```
bilge> /cd /path/to/other/project
  Working directory: /path/to/other/project
```

---

## Multi-Line Input

Use a trailing `\` to continue input on the next line:

```
bilge> Write a function that \
  ...> takes a filename and \
  ...> returns the line count.
```

The continuation prompt `...>` appears automatically. Lines are joined with newlines before being sent to the LLM.

---

## How It Works

Each time you send a message, Bilge follows this process:

1. **User message** is added to the conversation history
2. **Full context** (system prompt + conversation history) is sent to the LLM
3. The LLM may request **tool calls** (read a file, run a command, etc.)
4. Bilge **executes** each tool and feeds results back to the LLM
5. Steps 3-4 **repeat** until the LLM produces a final text response (up to 50 rounds)
6. The **response** is displayed along with a summary of tool executions

### Tool Execution Summary

When tools are used, Bilge displays a summary:
```
  ⚙ glob_files  **/*.jl  (12ms)
  ⚙ read_file  src/Bilge.jl  (3ms)
  ⚙ read_file  src/agent.jl  (2ms)

This project is a Julia package called Bilge.jl...

  [tokens: 2450 in / 180 out]
```

---

## Tips

!!! tip "Read Before Edit"
    The LLM is instructed to read files before making edits. This ensures it understands the existing code and makes accurate modifications.

!!! tip "Working Directory"
    All tool paths are resolved relative to the working directory. Use `/cd` to switch projects without restarting.

!!! tip "Token Usage"
    Monitor token usage with `/tokens`. Long conversations accumulate context — use `/clear` when switching tasks to keep costs down and improve response quality.
