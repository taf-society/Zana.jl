# Ollama Integration

Zana provides first-class support for [Ollama](https://ollama.ai/), allowing you to run a fully local AI coding copilot without any external API calls. This is ideal for privacy-sensitive work, offline development, or reducing API costs.

---

## Setup

### 1. Install Ollama

Follow the instructions at [ollama.ai](https://ollama.ai/) to install Ollama on your system.

### 2. Pull a Model

```bash
# Recommended models for coding tasks
ollama pull qwen3
ollama pull llama3.1
ollama pull codellama
```

### 3. Start Zana

```julia
using Zana

zana(ollama=true, model="qwen3")
```

---

## Verifying the Connection

Before starting Zana, you can check that Ollama is running:

```julia
using Zana

# Check if Ollama server is reachable
check_ollama_connection()  # Returns true/false

# List available models
list_ollama_models()  # Returns Vector{String}
```

!!! tip "Ollama Must Be Running"
    Ollama runs as a background service. If `check_ollama_connection()` returns `false`, start Ollama with:
    ```bash
    ollama serve
    ```

---

## Model Selection

### Recommended Models for Coding

| Model | Size | Strengths |
|-------|------|-----------|
| **`qwen3`** | 8B | Strong tool calling, good reasoning |
| **`qwen3-coder`** | 30B+ | Specialized for code generation |
| **`llama3.1`** | 8B/70B | General-purpose, good tool support |
| **`codellama`** | 7B/13B/34B | Code-focused, fast |
| **`deepseek-coder-v2`** | Various | Strong code generation |

!!! info "Model Size vs Quality"
    Larger models generally produce better results but require more RAM and are slower. For most coding tasks, 8B-30B models offer a good balance of quality and speed.

---

## Protocol Options

Ollama supports two API protocols. Zana works with both.

### Native API (Default)

Uses Ollama's native `/api/chat` endpoint:

```julia
zana(ollama=true, model="qwen3")
# Equivalent to:
zana(ollama=true, model="qwen3", use_openai_compat=false)
```

### OpenAI-Compatible API

Uses Ollama's `/v1/chat/completions` endpoint:

```julia
zana(ollama=true, model="qwen3", use_openai_compat=true)
```

!!! note "When to Use OpenAI-Compatible Mode"
    The native API is recommended for most cases. Use OpenAI-compatible mode if:
    - The model has better tool-calling support through the OpenAI format
    - You're debugging protocol issues
    - You want consistent behavior with OpenAI backends

---

## Remote Ollama Server

You can connect to an Ollama instance running on a different machine:

```julia
zana(
    ollama = true,
    model = "qwen3",
    host = "http://192.168.1.100:11434"
)
```

Or using the programmatic API:

```julia
config = ZanaConfig(
    ollama = OllamaConfig(
        model = "qwen3",
        host = "http://192.168.1.100:11434"
    )
)

agent = ZanaAgent(config, pwd())
```

---

## Utility Functions

### `check_ollama_connection`

```julia
check_ollama_connection(; host="http://localhost:11434") -> Bool
```

Checks if the Ollama server is running and reachable. Uses a 5-second connection timeout.

### `list_ollama_models`

```julia
list_ollama_models(; host="http://localhost:11434") -> Vector{String}
```

Returns a list of model names available on the Ollama server.

```julia
julia> list_ollama_models()
3-element Vector{String}:
 "qwen3:latest"
 "llama3.1:latest"
 "codellama:latest"
```

---

## Troubleshooting

**Problem:** `HTTP.IOError` or connection refused
- **Solution:** Make sure Ollama is running (`ollama serve`)

**Problem:** Model not found
- **Solution:** Pull the model first (`ollama pull model-name`)

**Problem:** Slow responses
- **Solution:** Use a smaller model or ensure sufficient RAM. Ollama requires roughly the model size in RAM (e.g., 8GB for an 8B model).

**Problem:** Poor tool calling
- **Solution:** Some models have limited tool-calling ability. Try `qwen3` or `llama3.1` which have strong support.
