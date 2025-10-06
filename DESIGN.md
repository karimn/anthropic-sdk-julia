# Design and Julia Conventions

This document outlines the Julia-specific design decisions and conventions used in this SDK.

## Julia Conventions Applied

### 1. Type System

#### Optional Type Alias
```julia
const Optional{T} = Union{T, Nothing}
```
- More readable than `Union{T, Nothing}` throughout the codebase
- Standard practice in Julia packages like DataFrames.jl

#### Abstract Types
```julia
abstract type AbstractContent end

struct TextContent <: AbstractContent
    # ...
end
```
- Used for content types to enable polymorphism
- Allows future extension without breaking changes

#### Type Annotations
```julia
function create(
    m::Messages;
    model::AbstractString,           # Accept any string type
    messages::AbstractVector,        # Accept any vector type
    max_tokens::Integer,             # Accept any integer type
    temperature::Optional{Real}=nothing  # Accept any numeric type
)
```
- Use abstract supertypes (`AbstractString`, `AbstractVector`, `Integer`, `Real`)
- More flexible and idiomatic than concrete types
- Allows SubString, Int64, Int32, Float64, etc.

### 2. Function Signatures

#### Keyword Arguments with Semicolon
```julia
# Julia convention: semicolon separates positional from keyword args
response = create(
    client.messages;  # Semicolon here!
    model="claude-sonnet-4-5-20250929",
    max_tokens=1024,
    messages=[Message("user", "Hello!")]
)
```
- Makes it clear which arguments are required vs optional
- Standard Julia convention for APIs

#### Constructor Flexibility
```julia
struct Message
    role::String
    content::Union{String, Vector{Any}}

    # Accept AbstractString but store as String
    Message(role::AbstractString, content) = new(String(role), content)
end
```
- Accept flexible input types
- Store in canonical form internally

### 3. Docstrings

#### Julia Docstring Format
```julia
"""
    create(messages::Messages; model, messages, max_tokens, kwargs...)

Create a message using the Anthropic API.

# Arguments
- `messages::Messages`: Messages API interface

# Required Keyword Arguments
- `model::AbstractString`: Model identifier

# Optional Keyword Arguments
- `temperature::Optional{Real}=nothing`: Sampling temperature ∈ [0.0, 1.0]

# Returns
- `MessageResponse` if `stream=false`

# Examples
```julia
client = Anthropic()
response = create(
    client.messages;
    model="claude-sonnet-4-5-20250929",
    max_tokens=1024,
    messages=[Message("user", "Hello!")]
)
\```
"""
```

Key elements:
- Function signature on first line
- Sections: Arguments, Returns, Examples, Throws
- Use backticks for code elements
- Unicode math symbols (∈) for mathematical notation

### 4. Error Handling

#### Custom Exception Types
```julia
struct AnthropicError <: Exception
    status::Int
    message::String
    type::String
end

function Base.showerror(io::IO, e::AnthropicError)
    print(io, "AnthropicError($(e.status)): $(e.type) - $(e.message)")
end
```
- Subtype `Exception` base type
- Implement `Base.showerror` for nice formatting
- Provides structured error information

### 5. String Handling

#### String Interpolation
```julia
# Good - using string() function
url = string(BASE_URL, endpoint)

# Also good - interpolation
message = "AnthropicError($(e.status)): $(e.type) - $(e.message)"
```

#### Efficient Buffer Operations
```julia
# String concatenation in loops
buffer = string(buffer, String(chunk))  # Allocates new string

# Index operations using prevind/nextind for Unicode safety
line = buffer[1:prevind(buffer, line_end)]
buffer = buffer[nextind(buffer, line_end):end]
```

### 6. Channel and Streaming

#### Using `do` Syntax with Channels
```julia
function _stream_request(m::Messages, body::Dict)
    Channel() do channel
        # Channel automatically closes when block exits
        response = make_request(...)

        for chunk in response.body
            # Process and put events
            put!(channel, event_data)
        end
    end
end
```
- Automatic resource cleanup
- Idiomatic Julia pattern for generators

### 7. Operator Overloading

#### Extending Base Functions
```julia
# Add convenience method for Usage
Base.:(+)(u::Usage) = u.input_tokens + u.output_tokens

# Usage:
total = +(response.usage)  # Returns total tokens
```
- Extends Julia's operator system
- Makes types feel native to the language

### 8. Code Organization

#### Section Headers
```julia
#####
##### Message Types
#####

# ... related code ...

#####
##### Tool Definition Types
#####

# ... related code ...
```
- Clear visual separation in longer files
- Standard in Julia Base and major packages

#### Module Structure
```julia
module AnthropicSDK

# Includes
include("types.jl")
include("http.jl")
include("messages.jl")
include("client.jl")

# Exports organized by category
export Optional
export Anthropic
export Message, MessageResponse, Usage
export create, stream, count_tokens

end
```

### 9. Performance Considerations

#### Type Stability
```julia
# Return consistent types
function create(m::Messages; stream::Bool=false, kwargs...)
    if stream
        return _stream_request(m, body)  # Returns Channel
    else
        return parse_response(response, MessageResponse)  # Returns MessageResponse
    end
end
```
- Separate `create()` and `stream()` functions for type stability
- Each returns predictable type

#### Parametric Types
```julia
function parse_response(response::HTTP.Response, ::Type{T}) where {T}
    return JSON3.read(String(response.body), T)
end
```
- Type parameter `T` allows compiler optimization
- Returns strongly-typed results

### 10. Naming Conventions

#### Snake Case for Internal Functions
```julia
# Public API - no underscore
function create(...)

# Internal helper - underscore prefix
function _stream_request(...)
```

#### Descriptive Names
```julia
# Good - clear and descriptive
function build_headers(api_key, api_version; extra_headers)
function handle_error_response(response)

# Avoid abbreviations unless very common
# max_tokens ✓ (common)
# msg ✗ (use message)
```

## Comparison with Python SDK

| Aspect | Python SDK | Julia SDK |
|--------|------------|-----------|
| Optional params | `Union[str, None]` | `Optional{AbstractString}` |
| Keyword args | `def fn(*, model, max_tokens)` | `function fn(; model, max_tokens)` |
| Type hints | `model: str` | `model::AbstractString` |
| Streaming | `with client.stream(...)` | `for event in stream(...)` |
| Errors | `class AnthropicError(Exception)` | `struct AnthropicError <: Exception` |
| Docstrings | Google/NumPy style | Julia docstring format |

## Best Practices Followed

1. **Accept abstract, store concrete**: Functions accept `AbstractString` but store `String`
2. **Type-stable functions**: Return types are predictable
3. **Comprehensive docstrings**: All public functions documented
4. **Examples in docs**: Every major function has usage examples
5. **Unicode support**: String operations use `prevind`/`nextind`
6. **Resource safety**: Channels auto-close, errors properly handled
7. **Idiomatic patterns**: `do` blocks, operator overloading, multiple dispatch

## Future Enhancements

Potential areas for future Julia-specific improvements:

1. **Multiple Dispatch**: Add specialized methods for different content types
2. **Traits**: Use traits for extensibility (e.g., StreamableModel trait)
3. **Async/Await**: Add `@async`/`@await` support for concurrent requests
4. **Broadcasting**: Support vectorized operations where appropriate
5. **Package Extensions**: Use package extensions for optional dependencies
6. **Precompilation**: Add PrecompileTools.jl for faster load times
