# Configuration

Bilge uses a nested configuration system with `BilgeConfig` as the top-level struct. You can configure either an OpenAI-compatible backend (`LLMConfig`) or a local Ollama backend (`OllamaConfig`).

---

## `BilgeConfig`

Top-level configuration. Set either `llm` or `ollama` (not both).

```julia
BilgeConfig(;
    llm::Union{LLMConfig, Nothing} = nothing,
    ollama::Union{OllamaConfig, Nothing} = nothing,
    max_tool_rounds::Int = 50,
    max_output_chars::Int = 100_000,
)
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `llm` | `Union{LLMConfig, Nothing}` | `nothing` | OpenAI-compatible backend configuration |
| `ollama` | `Union{OllamaConfig, Nothing}` | `nothing` | Ollama backend configuration |
| `max_tool_rounds` | `Int` | `50` | Maximum tool-call rounds per turn |
| `max_output_chars` | `Int` | `100_000` | Truncate tool output beyond this limit |

### Examples

```julia
# OpenAI backend
config = BilgeConfig(
    llm = LLMConfig(api_key="sk-...")
)

# Ollama backend
config = BilgeConfig(
    ollama = OllamaConfig(model="qwen3")
)

# Custom limits
config = BilgeConfig(
    ollama = OllamaConfig(model="qwen3"),
    max_tool_rounds = 100,
    max_output_chars = 200_000,
)
```

---

## `LLMConfig`

Configuration for OpenAI-compatible API backends.

```julia
LLMConfig(;
    api_key::String,
    model::String = "gpt-4o",
    base_url::String = "https://api.openai.com/v1",
    max_tokens::Int = 4096,
    temperature::Float64 = 0.1,
)
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `api_key` | `String` | *required* | API key for authentication |
| `model` | `String` | `"gpt-4o"` | Model identifier |
| `base_url` | `String` | `"https://api.openai.com/v1"` | API base URL |
| `max_tokens` | `Int` | `4096` | Maximum tokens in LLM response |
| `temperature` | `Float64` | `0.1` | Sampling temperature (lower = more deterministic) |

### Examples

```julia
# OpenAI GPT-4o (default)
llm = LLMConfig(api_key="sk-...")

# OpenAI with custom model
llm = LLMConfig(
    api_key = "sk-...",
    model = "gpt-4o-mini",
    max_tokens = 8192,
)

# Custom OpenAI-compatible API
llm = LLMConfig(
    api_key = "your-key",
    base_url = "https://api.together.xyz/v1",
    model = "meta-llama/Llama-3-70b-chat-hf",
)
```

!!! tip "API Key from Environment"
    When using the `bilge()` REPL function, the API key is automatically read from `ENV["OPENAI_API_KEY"]` if not provided explicitly.

---

## `OllamaConfig`

Configuration for the Ollama backend. Supports both the native Ollama API (`/api/chat`) and the OpenAI-compatible endpoint (`/v1/chat/completions`).

```julia
OllamaConfig(;
    model::String = "llama3.1",
    host::String = "http://localhost:11434",
    max_tokens::Int = 4096,
    temperature::Float64 = 0.1,
    use_openai_compat::Bool = false,
)
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `model` | `String` | `"llama3.1"` | Ollama model name |
| `host` | `String` | `"http://localhost:11434"` | Ollama server address |
| `max_tokens` | `Int` | `4096` | Maximum tokens in response |
| `temperature` | `Float64` | `0.1` | Sampling temperature |
| `use_openai_compat` | `Bool` | `false` | Use `/v1/chat/completions` instead of `/api/chat` |

### Examples

```julia
# Default Ollama (native API)
ollama = OllamaConfig(model="qwen3")

# Ollama with OpenAI-compatible endpoint
ollama = OllamaConfig(
    model = "qwen3",
    use_openai_compat = true,
)

# Remote Ollama server
ollama = OllamaConfig(
    model = "llama3.1",
    host = "http://192.168.1.100:11434",
    max_tokens = 8192,
)
```

!!! note "Native vs OpenAI-Compatible"
    The **native Ollama API** (`/api/chat`) is the default and generally works well. The **OpenAI-compatible endpoint** (`/v1/chat/completions`) can be useful for models that have better tool-calling support through the OpenAI format.

---

## State Types

### `BilgeState`

Mutable state maintained across the session. Created automatically by `BilgeAgent`.

| Field | Type | Description |
|-------|------|-------------|
| `working_directory` | `String` | Current working directory |
| `conversation_history` | `Vector{Message}` | Full conversation history |
| `turn_count` | `Int` | Number of completed turns |
| `total_tokens_in` | `Int` | Cumulative input tokens |
| `total_tokens_out` | `Int` | Cumulative output tokens |

### `TurnResult`

Returned by `process_turn` after each conversation turn.

| Field | Type | Description |
|-------|------|-------------|
| `response` | `String` | The LLM's final text response |
| `tool_executions` | `Vector{ToolExecution}` | Record of each tool call |
| `input_tokens` | `Int` | Tokens consumed this turn |
| `output_tokens` | `Int` | Tokens generated this turn |

### `ToolExecution`

Record of a single tool execution.

| Field | Type | Description |
|-------|------|-------------|
| `tool_name` | `String` | Name of the tool (e.g., `"read_file"`) |
| `arguments` | `Dict{String, Any}` | Arguments passed to the tool |
| `result` | `String` | JSON-serialized tool result |
| `duration_ms` | `Int` | Execution time in milliseconds |
