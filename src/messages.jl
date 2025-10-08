using JSON3

"""
    Messages(api_key, api_version)

Interface for the Anthropic Messages API.

This type is typically accessed via `client.messages` rather than constructed directly.
"""
struct Messages
    api_key::String
    api_version::String
end

"""
    create(messages::Messages; model, messages, max_tokens, kwargs...)

Create a message using the Anthropic API.

# Arguments
- `messages::Messages`: Messages API interface (accessed via `client.messages`)

# Required Keyword Arguments
- `model::AbstractString`: Model identifier (e.g., "claude-sonnet-4-5-20250929")
- `messages::AbstractVector`: Vector of Message objects
- `max_tokens::Integer`: Maximum tokens to generate

# Optional Keyword Arguments
- `system::Optional{AbstractString}=nothing`: System prompt
- `temperature::Optional{Real}=nothing`: Sampling temperature ∈ [0.0, 1.0]
- `top_p::Optional{Real}=nothing`: Nucleus sampling threshold
- `top_k::Optional{Integer}=nothing`: Top-k sampling parameter
- `metadata::Optional{Dict}=nothing`: Request metadata
- `stop_sequences::Optional{AbstractVector{<:AbstractString}}=nothing`: Custom stop sequences
- `tools::Optional{AbstractVector}=nothing`: Tool definitions
- `tool_choice::Optional{Dict}=nothing`: Tool selection strategy
- `stream::Bool=false`: Enable streaming responses

# Returns
- `MessageResponse` if `stream=false`
- `Channel` yielding streaming events if `stream=true`

# Examples
```julia
# Basic message
client = Anthropic()
response = create(
    client.messages;
    model="claude-sonnet-4-5-20250929",
    max_tokens=1024,
    messages=[Message("user", "Hello, Claude!")]
)

# With system prompt and temperature
response = create(
    client.messages;
    model="claude-sonnet-4-5-20250929",
    max_tokens=1024,
    system="You are a helpful assistant.",
    temperature=0.7,
    messages=[Message("user", "Explain quantum computing")]
)
```
"""
function create(
    m::Messages;
    model::AbstractString,
    messages::AbstractVector,
    max_tokens::Integer,
    system::Optional{AbstractString}=nothing,
    temperature::Optional{Real}=nothing,
    top_p::Optional{Real}=nothing,
    top_k::Optional{Integer}=nothing,
    metadata::Optional{Dict}=nothing,
    stop_sequences::Optional{AbstractVector{<:AbstractString}}=nothing,
    tools::Optional{AbstractVector}=nothing,
    tool_choice::Optional{Dict}=nothing,
    stream::Bool=false
)
    body = Dict{String, Any}(
        "model" => model,
        "messages" => messages,
        "max_tokens" => max_tokens
    )

    # Add optional parameters
    !isnothing(system) && (body["system"] = system)
    !isnothing(temperature) && (body["temperature"] = temperature)
    !isnothing(top_p) && (body["top_p"] = top_p)
    !isnothing(top_k) && (body["top_k"] = top_k)
    !isnothing(metadata) && (body["metadata"] = metadata)
    !isnothing(stop_sequences) && (body["stop_sequences"] = stop_sequences)
    !isnothing(tools) && (body["tools"] = tools)
    !isnothing(tool_choice) && (body["tool_choice"] = tool_choice)
    stream && (body["stream"] = true)

    if stream
        return _stream_request(m, body)
    else
        response = make_request(
            "POST",
            "/v1/messages",
            m.api_key;
            body=body,
            api_version=m.api_version
        )
        return parse_response(response, MessageResponse)
    end
end

"""
    count_tokens(messages::Messages; model, messages, kwargs...)

Count tokens in a message without generating a response.

# Arguments
- `messages::Messages`: Messages API interface

# Required Keyword Arguments
- `model::AbstractString`: Model identifier
- `messages::AbstractVector`: Vector of Message objects

# Optional Keyword Arguments
- `system::Optional{AbstractString}=nothing`: System prompt
- `tools::Optional{AbstractVector}=nothing`: Tool definitions

# Returns
- `CountTokensResponse`: Contains `input_tokens::Int` field

# Example
```julia
client = Anthropic()
token_count = count_tokens(
    client.messages;
    model="claude-sonnet-4-5-20250929",
    messages=[Message("user", "How many tokens is this?")]
)
println("Input tokens: ", token_count.input_tokens)
```
"""
function count_tokens(
    m::Messages;
    model::AbstractString,
    messages::AbstractVector,
    system::Optional{AbstractString}=nothing,
    tools::Optional{AbstractVector}=nothing
)
    body = Dict{String, Any}(
        "model" => model,
        "messages" => messages
    )

    !isnothing(system) && (body["system"] = system)
    !isnothing(tools) && (body["tools"] = tools)

    response = make_request(
        "POST",
        "/v1/messages/count_tokens",
        m.api_key;
        body=body,
        api_version=m.api_version
    )
    return parse_response(response, CountTokensResponse)
end

# Internal function for handling streaming requests
function _stream_request(m::Messages, body::Dict)
    Channel() do channel
        response = make_request(
            "POST",
            "/v1/messages",
            m.api_key;
            body,
            api_version=m.api_version,
            stream=true
        )

        buffer = UInt8[]
        for byte in response.body
            # HTTP.jl streaming returns individual UInt8 bytes
            push!(buffer, byte)

            # Process complete lines when we see a newline
            if byte == UInt8('\n')
                line = String(buffer[1:end-1])  # Exclude the newline
                buffer = UInt8[]  # Reset buffer

                # Skip empty lines
                isempty(strip(line)) && continue

                # Parse Server-Sent Events (SSE) format
                if startswith(line, "data: ")
                    data_str = line[7:end]

                    # End of stream marker
                    data_str == "[DONE]" && break

                    try
                        event_data = JSON3.read(data_str)

                        # Wrap in appropriate event struct based on type
                        event = if haskey(event_data, :type)
                            event_type = event_data.type
                            if event_type == "message_start"
                                MessageStartEvent(event_type, JSON3.read(JSON3.write(event_data.message), MessageResponse))
                            elseif event_type == "content_block_start"
                                ContentBlockStart(event_type, event_data.index, event_data.content_block)
                            elseif event_type == "content_block_delta"
                                ContentBlockDelta(event_type, event_data.index, event_data.delta)
                            elseif event_type == "content_block_stop"
                                ContentBlockStop(event_type, event_data.index)
                            elseif event_type == "message_delta"
                                MessageDelta(event_type, event_data.delta, event_data.usage)
                            elseif event_type == "message_stop"
                                MessageStop(event_type)
                            elseif event_type == "ping"
                                PingEvent(event_type)
                            else
                                # For unknown event types, return the raw JSON3.Object
                                event_data
                            end
                        else
                            event_data
                        end

                        put!(channel, event)
                    catch e
                        @warn "Failed to parse streaming event" line exception=(e, catch_backtrace())
                    end
                elseif startswith(line, "event: ")
                    # Event type line - currently unused but could be processed
                    continue
                end
            end
        end
    end
end

"""
    MessageStream

Wrapper around a streaming channel that provides convenience methods for text extraction.

# Fields
- `channel::Channel`: The underlying event channel
- `text_buffer::Vector{String}`: Accumulated text content

# Methods
- `text_stream(stream)`: Iterator that yields only text deltas
- `get_final_text(stream)`: Consumes stream and returns all text concatenated
"""
mutable struct MessageStream
    channel::Channel
    text_buffer::Vector{String}
    final_message::Union{Nothing, MessageResponse}

    MessageStream(channel::Channel) = new(channel, String[], nothing)
end

"""
    text_stream(stream::MessageStream)

Returns an iterator that yields only text content from the stream.

# Example
```julia
stream = MessageStream(client.messages; model="...", max_tokens=1024, messages=msgs)
for text in text_stream(stream)
    print(text)
end
```
"""
function text_stream(stream::MessageStream)
    Channel() do ch
        for event in stream.channel
            if event isa ContentBlockDelta
                if haskey(event.delta, :text)
                    text = String(event.delta.text)
                    push!(stream.text_buffer, text)
                    put!(ch, text)
                end
            elseif event isa MessageStartEvent
                stream.final_message = event.message
            end
        end
    end
end

"""
    get_final_text(stream::MessageStream)

Consumes the entire stream and returns all text content concatenated.

# Example
```julia
stream = MessageStream(client.messages; model="...", max_tokens=1024, messages=msgs)
text = get_final_text(stream)
println(text)
```
"""
function get_final_text(stream::MessageStream)
    for event in stream.channel
        if event isa ContentBlockDelta && haskey(event.delta, :text)
            push!(stream.text_buffer, String(event.delta.text))
        elseif event isa MessageStartEvent
            stream.final_message = event.message
        end
    end
    return join(stream.text_buffer)
end

"""
    MessageStream(messages::Messages; kwargs...) -> MessageStream

Create a MessageStream for convenient text extraction.

# Example - Direct usage
```julia
stream = MessageStream(client.messages; model="...", max_tokens=1024, messages=msgs)
for text in text_stream(stream)
    print(text)
end
```

# Example - Using do-block (Python's with equivalent)
```julia
MessageStream(client.messages; model="...", max_tokens=1024, messages=msgs) do stream
    for text in text_stream(stream)
        print(text)
    end
end
```
"""
function MessageStream(m::Messages; kwargs...)
    channel = create(m; stream=true, kwargs...)
    return MessageStream(channel)
end

"""
    MessageStream(f::Function, messages::Messages; kwargs...)

Execute a function with a MessageStream using do-block syntax.
This is Julia's equivalent to Python's `with` statement.

# Example
```julia
# Python equivalent:
# with client.messages.stream(model=..., max_tokens=..., messages=...) as stream:
#     for text in stream.text_stream:
#         print(text, end="")

# Julia version:
MessageStream(client.messages; model=..., max_tokens=..., messages=...) do stream
    for text in text_stream(stream)
        print(text)
    end
end
```
"""
function MessageStream(f::Function, m::Messages; kwargs...)
    stream = MessageStream(m; kwargs...)
    try
        f(stream)
    finally
        # Channel cleanup happens automatically via GC
        # but we ensure the stream is consumed if needed
        if isopen(stream.channel)
            close(stream.channel)
        end
    end
end

"""
    stream(messages::Messages; kwargs...)
    stream(f::Function, messages::Messages; kwargs...)

Create a streaming message request.

# Version 1: Returns a Channel
This is a convenience wrapper around `create` with `stream=true`.
Returns a `Channel` that yields streaming events.

# Version 2: Do-block with MessageStream
When called with a function (do-block), creates a MessageStream and passes it to the function.
This is Julia's equivalent to Python's `with` statement.

# Arguments
Same as `create()`, but `stream=true` is set automatically.

# Returns
- `Channel`: Yields streaming events (Version 1)
- Result of function call (Version 2)

# Example - Basic streaming
```julia
client = Anthropic()
for event in stream(
    client.messages;
    model="claude-sonnet-4-5-20250929",
    max_tokens=1024,
    messages=[Message("user", "Tell me a story")]
)
    # Check event type and extract text
    if event isa ContentBlockDelta && haskey(event.delta, :text)
        print(event.delta.text)
    end
end
```

# Example - Do-block syntax (like Python's with)
```julia
# Python:
# with client.messages.stream(...) as stream:
#     for text in stream.text_stream:
#         print(text, end="")

# Julia:
stream(client.messages; model="...", max_tokens=1024, messages=msgs) do s
    for text in text_stream(s)
        print(text)
    end
end
```

# Event Types
Streaming events include:
- `message_start`: Initial message metadata
- `content_block_start`: New content block begins
- `content_block_delta`: Incremental content (contains text)
- `content_block_stop`: Content block complete
- `message_delta`: Message-level updates
- `message_stop`: Stream complete
"""
function stream(m::Messages; kwargs...)
    create(m; stream=true, kwargs...)
end

# Do-block version that creates a MessageStream
function stream(f::Function, m::Messages; kwargs...)
    MessageStream(f, m; kwargs...)
end
