# Quick Start

## Installation

Install the development version:

```julia
using Pkg
Pkg.add(url="https://github.com/akai01/Bilge.jl")
```

Or for local development:

```julia
] dev /path/to/Bilge.jl
```

## REPL Interface (Recommended)

The REPL is the primary way to use Bilge. Start it with your preferred backend.

### Example 1: Ollama (Local Models)

```julia
using Bilge

# Start with a local Ollama model
bilge(ollama=true, model="qwen3")
```

!!! tip "Ollama Setup"
    Make sure Ollama is running locally before starting Bilge. You can verify with:
    ```julia
    using Bilge
    check_ollama_connection()  # Returns true if Ollama is reachable
    list_ollama_models()       # Lists available models
    ```

### Example 2: OpenAI

```julia
using Bilge

# Reads OPENAI_API_KEY from environment
bilge()

# Or pass the key directly
bilge(api_key="sk-...")
```

### Example 3: Custom OpenAI-Compatible API

```julia
using Bilge

bilge(
    api_key = "your-key",
    base_url = "https://api.example.com/v1",
    model = "your-model"
)
```

### Example 4: Advanced Configuration

```julia
using Bilge

# Full Ollama configuration
bilge(
    ollama = true,
    model = "qwen3",
    host = "http://localhost:11434",
    use_openai_compat = false,
    working_dir = "/path/to/your/project"
)
```

---

## Using the REPL

Once inside the Bilge REPL, you can ask the assistant to perform any coding task. The LLM has access to 7 tools and will autonomously decide which ones to use.

### Reading and Understanding Code

```
bilge> Read the main module file and explain the architecture

bilge> What does the process_turn function do?

bilge> Find all functions that handle HTTP requests
```

### Writing and Editing Code

```
bilge> Add a new function to parse JSON configuration files

bilge> Fix the bug in the error handling of read_file

bilge> Refactor the agent loop to support streaming responses
```

### Running Commands

```
bilge> Run the test suite and fix any failures

bilge> Check the git status and show recent commits

bilge> List all TODO comments in the codebase
```

### Multi-Line Input

Use a trailing `\` for complex prompts:

```
bilge> Write a function that \
  ...> takes a Vector{String} of file paths, \
  ...> reads each file, and \
  ...> returns a Dict mapping paths to contents.
```

### REPL Commands

| Command | Description |
|---------|-------------|
| `/help` | Show available commands |
| `/exit`, `/quit` | Exit Bilge |
| `/clear` | Clear conversation history |
| `/history` | Show conversation history |
| `/tokens` | Show cumulative token usage |
| `/cd PATH` | Change working directory |

---

## Programmatic Usage (Agent API)

For scripts and automation, use `BilgeAgent` directly without the REPL.

### Basic Usage

```julia
using Bilge

# Create a configuration
config = BilgeConfig(
    ollama = OllamaConfig(model="qwen3")
)

# Create an agent
agent = BilgeAgent(config, pwd())

# Process a single turn
result = process_turn(agent, "List all Julia files in this project")

println(result.response)
println("Tokens: $(result.input_tokens) in / $(result.output_tokens) out")
```

### Multi-Turn Conversation

```julia
using Bilge

config = BilgeConfig(
    ollama = OllamaConfig(model="qwen3")
)

agent = BilgeAgent(config, pwd())

# First turn: ask about the project
result1 = process_turn(agent, "What does this project do?")
println(result1.response)

# Second turn: follow-up (conversation context is maintained)
result2 = process_turn(agent, "Show me the main entry point")
println(result2.response)

# Third turn: request a change
result3 = process_turn(agent, "Add error handling to that function")
println(result3.response)

# Check what tools were used
for exec in result3.tool_executions
    println("  $(exec.tool_name) ($(exec.duration_ms)ms)")
end
```

### Inspecting Tool Executions

```julia
result = process_turn(agent, "Find and fix any type errors in src/")

# Each tool execution records what happened
for exec in result.tool_executions
    println("Tool: $(exec.tool_name)")
    println("  Args: $(exec.arguments)")
    println("  Duration: $(exec.duration_ms)ms")
    println("  Result: $(first(exec.result, 200))...")  # Preview
    println()
end
```

---

## Next Steps

!!! tip "Explore the Full Documentation"
    The Quick Start covers the basics. For detailed documentation on each feature:

**Documentation:**
- **[REPL Interface](repl.md)** — Full REPL documentation, commands, and session management
- **[Tools](tools.md)** — Detailed guide for all 7 coding tools
- **[Configuration](configuration.md)** — All configuration options for `BilgeConfig`, `LLMConfig`, and `OllamaConfig`
- **[Ollama Integration](ollama.md)** — Local model setup, model selection, and utilities
- **[API Reference](api.md)** — Complete API documentation
