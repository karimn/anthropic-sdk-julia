"""
    Anthropic(; api_key=nothing, api_version=DEFAULT_API_VERSION)

Create an Anthropic API client for interacting with Claude models.

# Keyword Arguments
- `api_key::Optional{AbstractString}=nothing`: API authentication key.
  If not provided, reads from `ANTHROPIC_API_KEY` environment variable.
- `api_version::AbstractString="2023-06-01"`: API version to use.

# Fields
- `api_key::String`: The API key being used
- `api_version::String`: The API version
- `messages::Messages`: Interface for the Messages API

# Throws
- `ErrorException`: If no API key is provided and `ANTHROPIC_API_KEY` is not set

# Examples
```julia
# Using environment variable (recommended)
ENV["ANTHROPIC_API_KEY"] = "sk-ant-..."
client = Anthropic()

# Using explicit API key
client = Anthropic(api_key="sk-ant-...")

# Specifying API version
client = Anthropic(api_version="2024-01-01")

# Making a request
response = create(
    client.messages;
    model="claude-sonnet-4-5-20250929",
    max_tokens=1024,
    messages=[Message("user", "Hello!")]
)
```
"""
struct Anthropic
    api_key::String
    api_version::String
    messages::Messages

    function Anthropic(;
        api_key::Optional{AbstractString}=nothing,
        api_version::AbstractString=DEFAULT_API_VERSION
    )
        # Retrieve API key from argument or environment
        key = if isnothing(api_key)
            env_key = get(ENV, "ANTHROPIC_API_KEY", nothing)
            isnothing(env_key) && error(
                "API key must be provided via the `api_key` parameter or " *
                "the ANTHROPIC_API_KEY environment variable"
            )
            env_key
        else
            String(api_key)
        end

        # Create Messages interface
        msgs = Messages(key, String(api_version))
        new(key, String(api_version), msgs)
    end
end
