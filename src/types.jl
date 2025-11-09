using StructTypes
using JSON3

# Define Optional type alias for cleaner code
const Optional{T} = Union{T, Nothing}

#####
##### Abstract Types
#####

abstract type AbstractContent end
StructTypes.StructType(::Type{AbstractContent}) = StructTypes.AbstractType()

# Tell StructTypes how to discriminate between AbstractContent subtypes
StructTypes.subtypekey(::Type{AbstractContent}) = :type
StructTypes.subtypes(::Type{AbstractContent}) = (
    text = TextContent,
    image = ImageContent,
    tool_use = ToolUseContent,
    tool_result = ToolResultContent
)

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
    properties::Dict{String, Dict{String, String}}
    required::Vector{String}
end
StructTypes.StructType(::Type{ToolInputSchema}) = StructTypes.Struct()

# Convenience constructor with default type
ToolInputSchema(properties::Dict{String, Dict{String, String}}, required::Vector{String}; type::String="object") =
    new(type, properties, required)

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

# Add this constructor
function Tool(d::Dict)
    JSON3.read(JSON3.write(d), Tool)
end

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
    content::Vector{AbstractContent}
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
    content_block::Any  # JSON3.Object or Dict
end
StructTypes.StructType(::Type{ContentBlockStart}) = StructTypes.Struct()

struct ContentBlockDelta
    type::String
    index::Int
    delta::Any  # JSON3.Object or Dict
end
StructTypes.StructType(::Type{ContentBlockDelta}) = StructTypes.Struct()

struct MessageStartEvent
    type::String
    message::MessageResponse
end
StructTypes.StructType(::Type{MessageStartEvent}) = StructTypes.Struct()

struct ContentBlockStop
    type::String
    index::Int
end
StructTypes.StructType(::Type{ContentBlockStop}) = StructTypes.Struct()

struct MessageDelta
    type::String
    delta::Any  # JSON3.Object or Dict
    usage::Any  # JSON3.Object or Dict
end
StructTypes.StructType(::Type{MessageDelta}) = StructTypes.Struct()

struct MessageStop
    type::String
end
StructTypes.StructType(::Type{MessageStop}) = StructTypes.Struct()

struct PingEvent
    type::String
end
StructTypes.StructType(::Type{PingEvent}) = StructTypes.Struct()

#####
##### Custom show methods for streaming events
#####

"""
Helper function to display field values in a readable format.
"""
function _show_field_value(io::IO, value)
    if value isa JSON3.Object
        # For nested objects, show type and key fields in a compact format
        if haskey(value, :type)
            type_val = value.type
            if type_val == "text_delta" && haskey(value, :text)
                # Show text deltas with their content
                text = String(value.text)
                if length(text) > 30
                    print(io, "text_delta(\"", text[1:27], "...\")")
                else
                    print(io, "text_delta(\"", text, "\")")
                end
            else
                print(io, type_val, "(...)")
            end
        else
            # Show object with count of fields
            print(io, "{", length(keys(value)), " fields}")
        end
    elseif value isa AbstractString
        # Show strings with quotes, truncate if too long
        str = String(value)
        if length(str) > 50
            print(io, '"', str[1:47], "...\"")
        else
            print(io, '"', str, '"')
        end
    elseif value isa AbstractDict
        print(io, "{", length(value), " fields}")
    elseif value isa AbstractArray
        print(io, "[", length(value), " items]")
    else
        print(io, value)
    end
end

# Show methods for specific event types
function Base.show(io::IO, event::ContentBlockStart)
    print(io, "ContentBlockStart(index=", event.index, ", content_block=")
    _show_field_value(io, event.content_block)
    print(io, ")")
end

function Base.show(io::IO, event::ContentBlockDelta)
    print(io, "ContentBlockDelta(index=", event.index, ", delta=")
    _show_field_value(io, event.delta)
    print(io, ")")
end

function Base.show(io::IO, event::MessageStartEvent)
    print(io, "MessageStartEvent(message=", event.message.id, ")")
end

function Base.show(io::IO, event::ContentBlockStop)
    print(io, "ContentBlockStop(index=", event.index, ")")
end

function Base.show(io::IO, event::MessageDelta)
    print(io, "MessageDelta(delta=")
    _show_field_value(io, event.delta)
    print(io, ", usage=")
    _show_field_value(io, event.usage)
    print(io, ")")
end

function Base.show(io::IO, event::MessageStop)
    print(io, "MessageStop()")
end

function Base.show(io::IO, event::PingEvent)
    print(io, "Ping()")
end

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
