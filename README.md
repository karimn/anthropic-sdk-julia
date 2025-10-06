# AnthropicSDK.jl

A Julia SDK for the Anthropic API, providing a clean interface to interact with Claude models.

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/karimn/anthropic-sdk-julia")
```

Or in the Julia REPL package mode:
```
] add https://github.com/karimn/anthropic-sdk-julia
```

## Quick Start

```julia
using AnthropicSDK

# Initialize the client (reads ANTHROPIC_API_KEY from environment)
client = Anthropic()

# Or provide API key explicitly
client = Anthropic(api_key="your-api-key-here")

# Create a message
response = create(
    client.messages,
    model="claude-sonnet-4-5-20250929",
    max_tokens=1024,
    messages=[Message("user", "Hello, Claude!")]
)

println(response.content[1]["text"])
```

## Features

- ✅ Messages API (create, stream, count_tokens)
- ✅ Streaming support
- ✅ Tool/function calling
- ✅ Token counting
- ✅ Error handling
- ✅ Type-safe request/response objects

## Usage Examples

### Basic Message Creation

```julia
using AnthropicSDK

client = Anthropic()

response = create(
    client.messages,
    model="claude-sonnet-4-5-20250929",
    max_tokens=1024,
    messages=[Message("user", "What is the capital of France?")]
)

println(response.content[1]["text"])
```

### Streaming Responses

```julia
using AnthropicSDK

client = Anthropic()

for event in stream(
    client.messages,
    model="claude-sonnet-4-5-20250929",
    max_tokens=1024,
    messages=[Message("user", "Tell me a short story")]
)
    if haskey(event, :type) && event.type == "content_block_delta"
        if haskey(event.delta, :text)
            print(event.delta.text)
        end
    end
end
```

### Using System Prompts

```julia
response = create(
    client.messages,
    model="claude-sonnet-4-5-20250929",
    max_tokens=1024,
    system="You are a helpful AI assistant specialized in mathematics.",
    messages=[Message("user", "What is 15 * 24?")]
)
```

### Multi-turn Conversations

```julia
conversation = [
    Message("user", "Hello! My name is Alice."),
    Message("assistant", "Hello Alice! Nice to meet you. How can I help you today?"),
    Message("user", "What's my name?")
]

response = create(
    client.messages,
    model="claude-sonnet-4-5-20250929",
    max_tokens=1024,
    messages=conversation
)
```

### Tool/Function Calling

```julia
tools = [
    Tool(
        "get_weather",
        "Get the current weather for a location",
        ToolInputSchema(
            Dict(
                "location" => Dict(
                    "type" => "string",
                    "description" => "The city and state, e.g. San Francisco, CA"
                )
            ),
            ["location"]
        )
    )
]

response = create(
    client.messages,
    model="claude-sonnet-4-5-20250929",
    max_tokens=1024,
    messages=[Message("user", "What's the weather in San Francisco?")],
    tools=tools
)

# Check if Claude wants to use a tool
for content in response.content
    if haskey(content, "type") && content["type"] == "tool_use"
        println("Tool: ", content["name"])
        println("Input: ", content["input"])
    end
end
```

### Counting Tokens

```julia
token_count = count_tokens(
    client.messages,
    model="claude-sonnet-4-5-20250929",
    messages=[Message("user", "Hello, how are you?")]
)

println("Input tokens: ", token_count.input_tokens)
```

### Temperature and Sampling Parameters

```julia
response = create(
    client.messages,
    model="claude-sonnet-4-5-20250929",
    max_tokens=1024,
    temperature=0.7,
    top_p=0.9,
    messages=[Message("user", "Write a creative story")]
)
```

### Stop Sequences

```julia
response = create(
    client.messages,
    model="claude-sonnet-4-5-20250929",
    max_tokens=1024,
    stop_sequences=["END", "STOP"],
    messages=[Message("user", "Count from 1 to 100")]
)
```

## API Reference

### Client

#### `Anthropic(; api_key=nothing, api_version="2023-06-01")`

Creates a new Anthropic client.

**Parameters:**
- `api_key`: Your API key (optional if `ANTHROPIC_API_KEY` environment variable is set)
- `api_version`: API version to use (default: "2023-06-01")

### Messages

#### `create(client.messages; kwargs...)`

Create a message.

**Required Parameters:**
- `model::String`: Model identifier
- `messages::Vector{Message}`: Conversation messages
- `max_tokens::Int`: Maximum tokens to generate

**Optional Parameters:**
- `system::String`: System prompt
- `temperature::Float64`: Randomness (0.0-1.0)
- `top_p::Float64`: Nucleus sampling threshold
- `top_k::Int`: Top-k sampling
- `stop_sequences::Vector{String}`: Custom stop sequences
- `tools::Vector{Tool}`: Available tools
- `tool_choice::Dict`: Tool choice strategy
- `stream::Bool`: Enable streaming

#### `stream(client.messages; kwargs...)`

Create a streaming message request. Same parameters as `create()`.

Returns a `Channel` that yields streaming events.

#### `count_tokens(client.messages; kwargs...)`

Count tokens without generating a response.

**Required Parameters:**
- `model::String`: Model identifier
- `messages::Vector{Message}`: Messages to count

**Optional Parameters:**
- `system::String`: System prompt
- `tools::Vector{Tool}`: Tool definitions

## Types

### Core Types

- `Message(role, content)`: Message object
- `MessageResponse`: API response
- `Usage`: Token usage information
- `CountTokensResponse`: Token count result

### Content Types

- `TextContent`: Text content block
- `ImageContent`: Image content block
- `ImageSource`: Image data source
- `ToolUseContent`: Tool usage block
- `ToolResultContent`: Tool result block

### Tool Types

- `Tool(name, description, input_schema)`: Tool definition
- `ToolInputSchema(properties, required)`: Tool input schema

### Errors

- `AnthropicError`: API error exception

## Environment Variables

- `ANTHROPIC_API_KEY`: Your Anthropic API key

## Models

Current supported models include:
- `claude-sonnet-4-5-20250929` (Claude Sonnet 4.5)
- `claude-3-7-sonnet-20250219` (Claude 3.7 Sonnet)
- `claude-3-5-sonnet-20241022` (Claude 3.5 Sonnet)
- `claude-3-5-haiku-20241022` (Claude 3.5 Haiku)
- `claude-3-opus-20240229` (Claude 3 Opus)

See the [Anthropic documentation](https://docs.claude.com) for the latest model list.

## Error Handling

```julia
try
    response = create(
        client.messages,
        model="claude-sonnet-4-5-20250929",
        max_tokens=1024,
        messages=[Message("user", "Hello!")]
    )
catch e
    if e isa AnthropicError
        println("API Error ($(e.status)): $(e.message)")
    else
        rethrow(e)
    end
end
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License

## Links

- [Anthropic API Documentation](https://docs.claude.com)
- [Python SDK](https://github.com/anthropics/anthropic-sdk-python)
- [TypeScript SDK](https://github.com/anthropics/anthropic-sdk-typescript)
