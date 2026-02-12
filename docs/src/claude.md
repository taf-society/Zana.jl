# Claude Integration

Zana provides native support for [Anthropic Claude](https://www.anthropic.com/) models, enabling you to use Claude as your coding copilot backend. This uses the Anthropic Messages API directly — no OpenAI compatibility layer needed.

---

## Setup

### 1. Get an API Key

Sign up at [console.anthropic.com](https://console.anthropic.com/) and create an API key.

### 2. Set the Environment Variable

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
```

### 3. Start Zana

```julia
using Zana

zana(claude=true)
```

---

## Quick Start

### Default (Claude Sonnet)

```julia
using Zana

# Reads ANTHROPIC_API_KEY from environment
zana(claude=true)
```

### Specific Model

```julia
using Zana

zana(claude=true, model="claude-opus-4-20250514")
```

### Pass API Key Directly

```julia
using Zana

zana(claude=true, api_key="sk-ant-...")
```

---

## Programmatic Usage

Use `ClaudeConfig` with `ZanaAgent` for scripting and automation:

```julia
using Zana

config = ZanaConfig(
    claude = ClaudeConfig(
        api_key = ENV["ANTHROPIC_API_KEY"],
        model = "claude-sonnet-4-20250514"
    )
)

agent = ZanaAgent(config, pwd())
result = process_turn(agent, "Explain the architecture of this project")

println(result.response)
println("Tokens: $(result.input_tokens) in / $(result.output_tokens) out")
```

---

## Configuration

### `ClaudeConfig`

```julia
ClaudeConfig(;
    api_key::String,
    model::String = "claude-sonnet-4-20250514",
    base_url::String = "https://api.anthropic.com",
    max_tokens::Int = 8192,
    temperature::Float64 = 0.1,
    api_version::String = "2023-06-01",
)
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `api_key` | `String` | *required* | Anthropic API key |
| `model` | `String` | `"claude-sonnet-4-20250514"` | Claude model identifier |
| `base_url` | `String` | `"https://api.anthropic.com"` | API base URL |
| `max_tokens` | `Int` | `8192` | Maximum tokens in response |
| `temperature` | `Float64` | `0.1` | Sampling temperature |
| `api_version` | `String` | `"2023-06-01"` | Anthropic API version header |

For the full configuration reference, see [Configuration](configuration.md).

---

## Available Models

| Model | Identifier | Strengths |
|-------|-----------|-----------|
| **Claude Sonnet 4** | `claude-sonnet-4-20250514` | Great balance of speed and capability (default) |
| **Claude Opus 4** | `claude-opus-4-20250514` | Most capable, best for complex tasks |
| **Claude Haiku 3.5** | `claude-haiku-4-5-20251001` | Fastest, good for simple tasks |

!!! tip "Model Selection"
    Claude Sonnet 4 is the default and recommended for most coding tasks. Use Opus for complex multi-file refactoring or architecture tasks. Use Haiku for quick questions and simple edits.

---

## How It Works

The Anthropic Messages API differs from OpenAI in several ways. Zana handles all of these automatically:

- **Authentication** — Uses `x-api-key` header instead of `Authorization: Bearer`
- **System prompt** — Sent as a top-level `system` parameter, not as a message
- **Tool format** — Tools use `input_schema` instead of `parameters`, without the `{"type":"function","function":{...}}` wrapper
- **Tool results** — Sent as `user` role messages with `tool_result` content blocks
- **Content blocks** — Responses use typed content blocks (`text`, `tool_use`) instead of plain strings

---

## Troubleshooting

**Problem:** `HTTP.StatusError` with 401
- **Solution:** Check that your `ANTHROPIC_API_KEY` is valid and not expired

**Problem:** `HTTP.StatusError` with 429
- **Solution:** You've hit the rate limit. Wait a moment and try again, or check your Anthropic plan limits

**Problem:** `HTTP.StatusError` with 400
- **Solution:** The model name may be invalid. Check available models at [docs.anthropic.com](https://docs.anthropic.com/en/docs/about-claude/models)

**Problem:** Responses seem truncated
- **Solution:** Increase `max_tokens` in `ClaudeConfig`. The default is 8192, but you can set it higher:
    ```julia
    zana(claude=true)  # uses 8192 by default
    # Or with programmatic API:
    ClaudeConfig(api_key="...", max_tokens=16384)
    ```
