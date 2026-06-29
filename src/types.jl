using JSON

# Define Optional type alias for cleaner code
const Optional{T} = Union{T, Nothing}

#####
##### Abstract Types
#####

abstract type AbstractContent end
abstract type AbstractMessage end

# Define polymorphic type selection based on the "type" discriminator field
JSON.@choosetype AbstractContent x -> begin
    # Handle both regular dicts and JSON.LazyValue
    # LazyValue needs JSON.parse to materialize the value
    type_val = if x isa JSON.LazyValue
        JSON.parse(x["type"], dicttype=Dict{Symbol, Any})
    else
        get(x, :type, nothing)
    end

    if type_val == "text"
        TextContent
    elseif type_val == "image"
        ImageContent
    elseif type_val == "tool_use"
        ToolUseContent
    elseif type_val == "tool_result"
        ToolResultContent
    else
        error("Unknown AbstractContent type: $type_val")
    end
end

#####
##### Message Content Types
#####

struct TextContent <: AbstractContent
    type::Symbol
    text::String
end

struct ImageSource
    type::Symbol
    media_type::String
    data::String
end

struct ImageContent <: AbstractContent
    type::Symbol
    source::ImageSource
end

# JSON serialization: convert Symbol type fields to strings
JSON.lower(x::TextContent) = Dict(:type => string(x.type), :text => x.text)
JSON.lower(x::ImageSource) = Dict(:type => string(x.type), :media_type => x.media_type, :data => x.data)
JSON.lower(x::ImageContent) = Dict(:type => string(x.type), :source => x.source)

# Global registry for tool functions
const TOOL_REGISTRY = Dict{String, Function}()

"""
    register_tool(name::String, func::Function)
    register_tool(func::Function)

Register a function to be called when a tool with the given name is used.

# Examples
```julia
function my_tool(arg1, arg2)
    # tool implementation
end

# Explicit name
register_tool("my_tool", my_tool)

# Auto-extract name
register_tool(my_tool)  # Registers as "my_tool"
```
"""
function register_tool(name::String, func::Function)
    TOOL_REGISTRY[name] = func
end

# Overload that auto-extracts function name
function register_tool(func::Function)
    name = string(nameof(func))
    register_tool(name, func)
end

JSON.@tags struct ToolUseContent <: AbstractContent
    type::Symbol
    id::String
    name::String
    input::Dict{Symbol, Any}
    func::Union{Function, Nothing} &(json=(ignore=true,),)  # Function reference for tool execution

    # Constructor that automatically looks up the function by name
    function ToolUseContent(type::Union{String, Symbol}, id::String, name::String, input::Dict{Symbol, Any}, ::Nothing)
        local func = get(TOOL_REGISTRY, name, nothing)
        new(Symbol(type), id, name, input, func)
    end

    # # Constructor with explicit func (for testing or manual construction)
    # ToolUseContent(type::Union{String, Symbol}, id::String, name::String, input::Dict{Symbol, Any}, func::Union{Function, Nothing}) =
    #     new(Symbol(type), id, name, input, func)
end

# JSON serialization for ToolUseContent - override @tags behavior for type field
JSON.lower(x::ToolUseContent) = Dict(
    :type => string(x.type),
    :id => x.id,
    :name => x.name,
    :input => x.input
)

struct ToolResultContent <: AbstractContent
    type::Symbol
    tool_use_id::String
    content::Union{String, Vector{Any}}
    is_error::Optional{Bool}
end

# Constructor with default is_error=nothing
ToolResultContent(type::Union{String, Symbol}, tool_use_id::String, content::Union{String, Vector{Any}}) =
    ToolResultContent(Symbol(type), tool_use_id, content, nothing)

# JSON serialization for ToolResultContent
JSON.lower(x::ToolResultContent) = Dict(
    :type => string(x.type),
    :tool_use_id => x.tool_use_id,
    :content => x.content,
    :is_error => x.is_error
)

"""
    execute_tool(tool_use::ToolUseContent) -> ToolResultContent

Execute a tool and wrap the result in a ToolResultContent.

# Arguments
- `tool_use::ToolUseContent`: The tool use request from the API

# Returns
- `ToolResultContent`: The result wrapped for sending back to the API
  - On success: `is_error=false` (or nothing)
  - On error: `is_error=true` with error message

# Throws
- `ErrorException`: If the tool has no associated function

# Examples
```julia
# After receiving a ToolUseContent from the API
tool_use = response.content[1]  # Assuming first content is tool_use

# Execute and get result
result = execute_tool(tool_use)

# Send result back in next message
response = create(
    client.messages;
    model="claude-sonnet-4-5-20250929",
    max_tokens=1024,
    messages=[
        Message("user", "What's the weather?"),
        Message("assistant", [tool_use]),
        Message("user", [result])
    ]
)
```
"""
function execute_tool(tool_use::ToolUseContent)
    if isnothing(tool_use.func)
        error("Tool '$(tool_use.name)' has no associated function. Did you register it?")
    end

    try
        # Extract arguments from input dict
        # The function is called with keyword arguments from the input dict
        result = tool_use.func(; tool_use.input...)

        # Wrap the result in ToolResultContent
        return ToolResultContent(
            "tool_result",
            tool_use.id,
            string(result),
            false
        )
    catch e
        # If execution fails, return error as tool result
        error_message = "Error executing tool '$(tool_use.name)': $(sprint(showerror, e))"
        return ToolResultContent(
            "tool_result",
            tool_use.id,
            error_message,
            true
        )
    end
end

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
struct Message <: AbstractMessage
    role::Symbol
    content::Union{String, Vector{<:AbstractContent}}

    # Constructor that accepts AbstractString for role
    function Message(role::Union{AbstractString, Symbol}, content::Union{String, Vector{<:AbstractContent}})
        new(Symbol(role), content)
    end
end

# JSON serialization for Message
JSON.lower(x::Message) = Dict(:role => string(x.role), :content => x.content)

"""
    Base.string(msg::AbstractMessage)

Convert a message to a string by extracting text from its content field.

For messages with string content, returns the string directly.
For messages with structured content blocks, extracts and concatenates text from TextContent blocks.

# Examples
```julia
msg = Message("user", "Hello!")
string(msg)  # Returns: "Hello!"

response = MessageResponse(...)  # with TextContent blocks
string(response)  # Returns concatenated text from all TextContent blocks
```
"""
function Base.string(msg::AbstractMessage)
    if msg.content isa String
        return msg.content
    else
        # Extract text from all TextContent blocks
        text_parts = String[]
        for block in msg.content
            if block isa TextContent
                push!(text_parts, block.text)
            end
        end
        return join(text_parts, "")
    end
end

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
    type::Symbol
    properties::Dict{String, Dict{String, Any}}
    required::Vector{String}
end

# Convenience constructor with default type
function ToolInputSchema(properties::Dict{String, Dict{String, Any}}, required::Vector{String}; type::Union{String, Symbol}="object")
    return ToolInputSchema(Symbol(type), properties, required)
end

# Flexible constructor that accepts any Dict type (e.g., Dict{String, Dict{String, String}})
function ToolInputSchema(properties::Dict, required::Vector{String}; type::Union{String, Symbol}="object")
    # Convert to the required type
    converted_props = Dict{String, Dict{String, Any}}(
        k => Dict{String, Any}(v) for (k, v) in properties
    )
    return ToolInputSchema(Symbol(type), converted_props, required)
end

# Constructor from a complete schema dict
function ToolInputSchema(schema::Dict)
    props = get(schema, "properties", Dict())
    req = get(schema, "required", String[])
    type_val = get(schema, "type", "object")

    # Convert properties to the required type
    converted_props = Dict{String, Dict{String, Any}}(
        k => Dict{String, Any}(v) for (k, v) in props
    )

    return ToolInputSchema(Symbol(type_val), converted_props, req)
end

# JSON serialization for ToolInputSchema
JSON.lower(x::ToolInputSchema) = Dict(
    :type => string(x.type),
    :properties => x.properties,
    :required => x.required
)

"""
    Tool(name, description, input_schema)
    Tool(func, description, input_schema)

Definition of a tool that Claude can use.

# Arguments
- `name::String`: Unique tool name
- `func::Function`: Function to execute (name auto-extracted, must use keyword args only)
- `description::String`: What the tool does
- `input_schema::Union{ToolInputSchema, Dict}`: Parameter schema

# Examples
```julia
# Auto-extract function name with Dict schema
function get_weather(; location::String, unit::String="fahrenheit")
    # implementation
end

tool = Tool(
    get_weather,
    "Get weather info",
    Dict(
        "type" => "object",
        "properties" => Dict(
            "location" => Dict("type" => "string"),
            "unit" => Dict("type" => "string")
        ),
        "required" => ["location"]
    )
)

# Or with ToolInputSchema
schema = ToolInputSchema(
    Dict("location" => Dict("type" => "string")),
    ["location"]
)
tool = Tool(get_weather, "Get weather info", schema)

# Manual name specification
tool = Tool("custom_name", "Description", schema)
```
"""
JSON.@tags struct Tool 
    name::String
    description::String
    input_schema::ToolInputSchema
    func::Union{Function, Nothing} &(json=(ignore=true,),)
end

# Constructor with explicit name (no function)
Tool(name::String, description::String, input_schema::ToolInputSchema) =
    Tool(name, description, input_schema, nothing)

function Tool(name::String, description::String, d::Dict)
    input_schema = ToolInputSchema(d) 
    return Tool(name, description, input_schema, nothing)
end

# Constructor with function - auto-extract name and register
function Tool(func::Function, description::String, input_schema::ToolInputSchema)
    name = string(nameof(func))

    # Validate that the function only accepts keyword arguments
    methods_list = methods(func)
    if length(methods_list) == 0
        error("Function '$name' has no methods defined")
    end

    # Check the first method (most specific)
    method = first(methods_list)
    sig = method.sig

    # Get the number of positional parameters (excluding the function itself)
    # sig.parameters[1] is the function type, rest are arguments
    if length(sig.parameters) > 1
        # Check if it has any non-keyword positional arguments
        # In Julia, keyword-only functions show up with sig.parameters of length 1 (just the function)
        # or all parameters after the function are in the kwsorter
        error("Tool function '$name' must only accept keyword arguments. Define it like: function $name(; arg1, arg2, ...)")
    end

    register_tool(name, func)
    return Tool(name, description, input_schema, func)
end

# Constructor with function and Dict for input_schema
function Tool(func::Function, description::String, input_schema::Dict)
    schema = ToolInputSchema(input_schema)
    return Tool(func, description, schema)
end

# Constructor to convert Dict to Tool

function BatchedTool()
    schema = Dict(
        "type" => "object",
        "properties" => Dict(
            "invocations" => Dict(
                "type" => "array",
                "description" => "The tool calls to invoke",
                "items" => Dict(
                    "type" => "object",
                    "properties" => Dict(
                        "name" => Dict(
                            "type" => "string",
                            "description" => "The name of the tool to invoke"
                        ),
                        "arguments" => Dict(
                            "type" => "string",
                            "description" => "The arguments to the tool, encoded as a JSON string"
                        )
                    ),
                    "required" => ["name", "arguments"]
                )
            )
        ),
        "required" => ["invocations"]
    )

    function batch_tool__(; invocations)
        results = []

        for (idx, inv) in enumerate(invocations)
            # Extract name and parse the arguments JSON string
            tool_name = String(inv[:name])
            args_dict = JSON.parse(inv[:arguments], dicttype=Dict{Symbol, Any})

            # Create a ToolUseContent object
            # The constructor will automatically look up the function from TOOL_REGISTRY
            tool_use = ToolUseContent(
                "tool_use",
                "$(tool_name)_$(idx)",  # Generate ID from tool name and index
                tool_name,
                args_dict,
                nothing  # This triggers the automatic func lookup in the constructor
            )

            # Execute the tool using the existing execute_tool function
            result = execute_tool(tool_use)
            push!(results, result)
        end

        return results
    end

    return Tool(batch_tool__, "Invoke multiple other tool calls simultaneously", schema) 
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
- `type::Symbol`: Response type (always :message)
- `role::Symbol`: Always :assistant
- `content::Vector{AbstractContent}`: Response content blocks
- `model::String`: Model that generated the response
- `stop_reason::Optional{Symbol}`: Why generation stopped (e.g., :end_turn, :max_tokens, :stop_sequence)
- `stop_sequence::Optional{String}`: Stop sequence that triggered
- `usage::Usage`: Token usage information
"""
struct MessageResponse <: AbstractMessage
    id::String
    type::Symbol
    role::Symbol
    content::Vector{AbstractContent}
    model::String
    stop_reason::Optional{Symbol}
    stop_sequence::Optional{String}
    usage::Usage
end

# JSON serialization for MessageResponse
JSON.lower(x::MessageResponse) = Dict(
    :id => x.id,
    :type => string(x.type),
    :role => string(x.role),
    :content => x.content,
    :model => x.model,
    :stop_reason => isnothing(x.stop_reason) ? nothing : string(x.stop_reason),
    :stop_sequence => x.stop_sequence,
    :usage => x.usage
)

"""
    CountTokensResponse(input_tokens)

Response from the count_tokens endpoint.
"""
struct CountTokensResponse
    input_tokens::Int
end

#####
##### Streaming Event Types
#####

struct StreamEvent
    type::Symbol
    data::Dict{Symbol, Any}
end

struct ContentBlockStart
    type::Symbol
    index::Int
    content_block::Any  # Dict from JSON parsing
end

struct ContentBlockDelta
    type::Symbol
    index::Int
    delta::Any  # Dict from JSON parsing
end

struct MessageStartEvent
    type::Symbol
    message::MessageResponse
end

struct ContentBlockStop
    type::Symbol
    index::Int
end

struct MessageDelta
    type::Symbol
    delta::Any  # Dict from JSON parsing
    usage::Any  # Dict from JSON parsing
end

struct MessageStop
    type::Symbol
end

struct PingEvent
    type::Symbol
end

# JSON serialization for streaming events
JSON.lower(x::StreamEvent) = Dict(:type => string(x.type), :data => x.data)
JSON.lower(x::ContentBlockStart) = Dict(:type => string(x.type), :index => x.index, :content_block => x.content_block)
JSON.lower(x::ContentBlockDelta) = Dict(:type => string(x.type), :index => x.index, :delta => x.delta)
JSON.lower(x::MessageStartEvent) = Dict(:type => string(x.type), :message => x.message)
JSON.lower(x::ContentBlockStop) = Dict(:type => string(x.type), :index => x.index)
JSON.lower(x::MessageDelta) = Dict(:type => string(x.type), :delta => x.delta, :usage => x.usage)
JSON.lower(x::MessageStop) = Dict(:type => string(x.type))
JSON.lower(x::PingEvent) = Dict(:type => string(x.type))

#####
##### Custom show methods for streaming events
#####

"""
Helper function to display field values in a readable format.
"""
function _show_field_value(io::IO, value)
    if value isa AbstractDict
        # For nested objects, show type and key fields in a compact format
        if haskey(value, :type)
            type_val = value[:type]
            if type_val == "text_delta" && haskey(value, :text)
                # Show text deltas with their content
                text = String(value[:text])
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
- `type::Symbol`: Error type identifier
"""
struct AnthropicError <: Exception
    status::Int
    message::String
    type::Symbol
end

function Base.showerror(io::IO, e::AnthropicError)
    print(io, "AnthropicError($(e.status)): $(e.type) - $(e.message)")
end

# JSON serialization for AnthropicError
JSON.lower(x::AnthropicError) = Dict(
    :status => x.status,
    :message => x.message,
    :type => string(x.type)
)
