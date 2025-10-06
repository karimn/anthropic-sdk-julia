using HTTP
using JSON3

const BASE_URL = "https://api.anthropic.com"
const DEFAULT_API_VERSION = "2023-06-01"

"""
    build_headers(api_key, api_version; extra_headers)

Build HTTP headers for Anthropic API requests.

# Arguments
- `api_key::AbstractString`: API authentication key
- `api_version::AbstractString=$DEFAULT_API_VERSION`: API version string
- `extra_headers::Dict{String,String}=Dict{String,String}()`: Additional headers

# Returns
- `Vector{Pair{String,String}}`: Headers suitable for HTTP.jl
"""
function build_headers(
    api_key::AbstractString,
    api_version::AbstractString=DEFAULT_API_VERSION;
    extra_headers::Dict{String,String}=Dict{String,String}()
)
    headers = Dict{String,String}(
        "x-api-key" => api_key,
        "anthropic-version" => api_version,
        "content-type" => "application/json",
        "user-agent" => "anthropic-sdk-julia/0.1.0"
    )
    merge!(headers, extra_headers)
    return [k => v for (k, v) in headers]
end

"""
    make_request(method, endpoint, api_key; kwargs...)

Make an HTTP request to the Anthropic API.

# Arguments
- `method::AbstractString`: HTTP method ("GET", "POST", etc.)
- `endpoint::AbstractString`: API endpoint path
- `api_key::AbstractString`: API authentication key

# Keyword Arguments
- `body::Optional{Dict}=nothing`: Request body as a dictionary
- `api_version::AbstractString=$DEFAULT_API_VERSION`: API version
- `extra_headers::Dict{String,String}=Dict{String,String}()`: Additional headers
- `stream::Bool=false`: Whether to stream the response

# Returns
- `HTTP.Response`: The HTTP response object
"""
function make_request(
    method::AbstractString,
    endpoint::AbstractString,
    api_key::AbstractString;
    body::Optional{Dict}=nothing,
    api_version::AbstractString=DEFAULT_API_VERSION,
    extra_headers::Dict{String,String}=Dict{String,String}(),
    stream::Bool=false
)
    url = string(BASE_URL, endpoint)
    headers = build_headers(api_key, api_version; extra_headers)

    try
        response = if method == "POST"
            if stream
                HTTP.post(url, headers, JSON3.write(body); stream=true)
            else
                HTTP.post(url, headers, JSON3.write(body))
            end
        elseif method == "GET"
            HTTP.get(url, headers)
        else
            error("Unsupported HTTP method: $method")
        end

        # Check for errors
        response.status >= 400 && handle_error_response(response)

        return response
    catch e
        if e isa HTTP.ExceptionRequest.StatusError
            handle_error_response(e.response)
        else
            rethrow(e)
        end
    end
end

"""
    handle_error_response(response)

Parse and throw an AnthropicError from an HTTP error response.

# Arguments
- `response::HTTP.Response`: Error response from the API
"""
function handle_error_response(response::HTTP.Response)
    try
        error_data = JSON3.read(String(response.body))
        error_type = get(error_data, :type, "unknown_error")
        error_message = get(get(error_data, :error, Dict()), :message, "Unknown error")
        throw(AnthropicError(response.status, error_message, String(error_type)))
    catch e
        e isa AnthropicError && rethrow(e)
        throw(AnthropicError(response.status, "Failed to parse error response", "unknown_error"))
    end
end

"""
    parse_response(response, T)

Parse an HTTP response body into a Julia type.

# Arguments
- `response::HTTP.Response`: HTTP response object
- `T::Type`: Type to parse the response into

# Returns
- Instance of type `T` parsed from the response
"""
function parse_response(response::HTTP.Response, ::Type{T}) where {T}
    return JSON3.read(String(response.body), T)
end
