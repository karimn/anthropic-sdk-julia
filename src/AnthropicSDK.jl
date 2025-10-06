"""
    AnthropicSDK

Julia SDK for the Anthropic API, providing access to Claude models.

# Quick Start
```julia
using AnthropicSDK

# Initialize client (reads ANTHROPIC_API_KEY from environment)
client = Anthropic()

# Create a message
response = create(
    client.messages;
    model="claude-sonnet-4-5-20250929",
    max_tokens=1024,
    messages=[Message("user", "Hello, Claude!")]
)

# Stream a response
for event in stream(
    client.messages;
    model="claude-sonnet-4-5-20250929",
    max_tokens=1024,
    messages=[Message("user", "Tell me a story")]
)
    if haskey(event, :type) && event.type == "content_block_delta"
        haskey(event.delta, :text) && print(event.delta.text)
    end
end
```

# Exported Types
- `Anthropic`: Main client
- `Message`: Conversation message
- `MessageResponse`: API response
- `Usage`: Token usage information
- `Tool`: Tool definition for function calling
- `Optional{T}`: Type alias for `Union{T, Nothing}`

# Exported Functions
- `create`: Create a message
- `stream`: Create a streaming message
- `count_tokens`: Count tokens without generating
"""
module AnthropicSDK

# Include module files in dependency order
include("types.jl")
include("http.jl")
include("messages.jl")
include("client.jl")

#####
##### Exports
#####

# Type alias
export Optional

# Main client
export Anthropic

# Core types
export Message, MessageResponse, Usage, CountTokensResponse

# Content types
export AbstractContent, TextContent, ImageContent, ImageSource
export ToolUseContent, ToolResultContent

# Tool types
export Tool, ToolInputSchema

# Error types
export AnthropicError

# API functions
export create, stream, count_tokens

end # module AnthropicSDK
