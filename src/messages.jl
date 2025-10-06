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

        buffer = ""
        for chunk in response.body
            buffer = string(buffer, String(chunk))

            # Process complete lines
            while occursin("\n", buffer)
                line_end = findfirst('\n', buffer)
                line = buffer[1:prevind(buffer, line_end)]
                buffer = buffer[nextind(buffer, line_end):end]

                # Skip empty lines
                isempty(strip(line)) && continue

                # Parse Server-Sent Events (SSE) format
                if startswith(line, "data: ")
                    data_str = line[7:end]

                    # End of stream marker
                    data_str == "[DONE]" && break

                    try
                        event_data = JSON3.read(data_str)
                        put!(channel, event_data)
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
    stream(messages::Messages; kwargs...)

Create a streaming message request.

This is a convenience wrapper around `create` with `stream=true`.
Returns a `Channel` that yields streaming events.

# Arguments
Same as `create()`, but `stream=true` is set automatically.

# Returns
- `Channel`: Yields JSON objects representing streaming events

# Example
```julia
client = Anthropic()
for event in stream(
    client.messages;
    model="claude-sonnet-4-5-20250929",
    max_tokens=1024,
    messages=[Message("user", "Tell me a story")]
)
    # Check event type and extract text
    if haskey(event, :type) && event.type == "content_block_delta"
        haskey(event, :delta) && haskey(event.delta, :text) && print(event.delta.text)
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
