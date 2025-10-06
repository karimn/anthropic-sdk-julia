using StructTypes

# Define Optional type alias for cleaner code
const Optional{T} = Union{T, Nothing}

#####
##### Abstract Types
#####

abstract type AbstractContent end

#####
##### Message Content Types
#####

struct TextContent <: AbstractContent
    type::String
    text::String
end
StructTypes.StructType(::Type{TextContent}) = StructTypes.Struct()

struct ImageSource
    type::String
    media_type::String
    data::String
end
StructTypes.StructType(::Type{ImageSource}) = StructTypes.Struct()

struct ImageContent <: AbstractContent
    type::String
    source::ImageSource
end
StructTypes.StructType(::Type{ImageContent}) = StructTypes.Struct()

struct ToolUseContent <: AbstractContent
    type::String
    id::String
    name::String
    input::Dict{String, Any}
end
StructTypes.StructType(::Type{ToolUseContent}) = StructTypes.Struct()

struct ToolResultContent <: AbstractContent
    type::String
    tool_use_id::String
    content::Union{String, Vector{Any}}
end
StructTypes.StructType(::Type{ToolResultContent}) = StructTypes.Struct()

#####
##### Message Types
#####

"""
    Message(role::AbstractString, content)

Represents a message in a conversation with Claude.

# Arguments
- `role::AbstractString`: Either "user" or "assistant"
- `content`: String or Vector of content blocks

# Examples
```julia
# Simple text message
msg = Message("user", "Hello, Claude!")

# Message with structured content
msg = Message("user", [
    Dict("type" => "text", "text" => "What's in this image?"),
    Dict("type" => "image", "source" => ...)
])
```
"""
struct Message
    role::String
    content::Union{String, Vector{Any}}

    # Constructor that accepts AbstractString for role
    Message(role::AbstractString, content) = new(String(role), content)
end
StructTypes.StructType(::Type{Message}) = StructTypes.Struct()

#####
##### Tool Definition Types
#####

"""
    ToolInputSchema(properties, required; type="object")

Schema defining the input parameters for a tool.

# Arguments
- `properties::Dict{String, Any}`: Parameter definitions
- `required::Vector{String}`: Required parameter names
- `type::String="object"`: Schema type (usually "object")
"""
struct ToolInputSchema
    type::String
    properties::Dict{String, Any}
    required::Vector{String}

    # Convenience constructor with default type
    ToolInputSchema(properties::Dict{String, Any}, required::Vector{String}; type::String="object") =
        new(type, properties, required)
end
StructTypes.StructType(::Type{ToolInputSchema}) = StructTypes.Struct()

"""
    Tool(name, description, input_schema)

Definition of a tool that Claude can use.

# Arguments
- `name::String`: Unique tool name
- `description::String`: What the tool does
- `input_schema::ToolInputSchema`: Parameter schema
"""
struct Tool
    name::String
    description::String
    input_schema::ToolInputSchema
end
StructTypes.StructType(::Type{Tool}) = StructTypes.Struct()

#####
##### Usage Tracking
#####

"""
    Usage(input_tokens, output_tokens)

Token usage information for a request.
"""
struct Usage
    input_tokens::Int
    output_tokens::Int
end
StructTypes.StructType(::Type{Usage}) = StructTypes.Struct()

# Add convenience method to get total tokens
Base.:(+)(u::Usage) = u.input_tokens + u.output_tokens

#####
##### Response Types
#####

"""
    MessageResponse

Response from the Messages API containing Claude's generated message.

# Fields
- `id::String`: Unique message identifier
- `type::String`: Response type ("message")
- `role::String`: Always "assistant"
- `content::Vector{Any}`: Response content blocks
- `model::String`: Model that generated the response
- `stop_reason::Optional{String}`: Why generation stopped
- `stop_sequence::Optional{String}`: Stop sequence that triggered
- `usage::Usage`: Token usage information
"""
struct MessageResponse
    id::String
    type::String
    role::String
    content::Vector{Any}
    model::String
    stop_reason::Optional{String}
    stop_sequence::Optional{String}
    usage::Usage
end
StructTypes.StructType(::Type{MessageResponse}) = StructTypes.Struct()

"""
    CountTokensResponse(input_tokens)

Response from the count_tokens endpoint.
"""
struct CountTokensResponse
    input_tokens::Int
end
StructTypes.StructType(::Type{CountTokensResponse}) = StructTypes.Struct()

#####
##### Streaming Event Types
#####

struct StreamEvent
    type::String
    data::Dict{String, Any}
end

struct ContentBlockStart
    type::String
    index::Int
    content_block::Dict{String, Any}
end
StructTypes.StructType(::Type{ContentBlockStart}) = StructTypes.Struct()

struct ContentBlockDelta
    type::String
    index::Int
    delta::Dict{String, Any}
end
StructTypes.StructType(::Type{ContentBlockDelta}) = StructTypes.Struct()

struct MessageStartEvent
    type::String
    message::MessageResponse
end
StructTypes.StructType(::Type{MessageStartEvent}) = StructTypes.Struct()

#####
##### Error Types
#####

"""
    AnthropicError(status, message, type)

Exception thrown when the Anthropic API returns an error.

# Fields
- `status::Int`: HTTP status code
- `message::String`: Error message
- `type::String`: Error type identifier
"""
struct AnthropicError <: Exception
    status::Int
    message::String
    type::String
end

function Base.showerror(io::IO, e::AnthropicError)
    print(io, "AnthropicError($(e.status)): $(e.type) - $(e.message)")
end
