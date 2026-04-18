using Test
using AnthropicSDK
using JSON
using StructTypes

@testset "AnthropicSDK.jl" begin

    @testset "JSON Migration - String Keys" begin
        # JSON.parse returns string keys, not symbols
        json_str = """{"type": "text", "text": "hello"}"""
        parsed = JSON.parse(json_str)
        @test haskey(parsed, "type")
        @test !haskey(parsed, :type)
        @test parsed["type"] == "text"

        # SDK deserialization pipeline works with symbol-keyed dicts (via _sym_dict internally)
        sym_parsed = JSON.parse(json_str, dicttype=Dict{Symbol,Any})
        content = StructTypes.constructfrom(TextContent, sym_parsed)
        @test content isa TextContent
        @test content.text == "hello"
    end

    @testset "TextContent Deserialization" begin
        json_str = """
        {
            "type": "text",
            "text": "Hello, world!"
        }
        """

        parsed = JSON.parse(json_str, dicttype=Dict{Symbol,Any})
        content = StructTypes.constructfrom(TextContent, parsed)

        @test content isa TextContent
        @test content.type == "text"
        @test content.text == "Hello, world!"
    end

    @testset "ImageContent Deserialization" begin
        json_str = """
        {
            "type": "image",
            "source": {
                "type": "base64",
                "media_type": "image/png",
                "data": "iVBORw0KG..."
            }
        }
        """

        parsed = JSON.parse(json_str, dicttype=Dict{Symbol,Any})
        content = StructTypes.constructfrom(ImageContent, parsed)

        @test content isa ImageContent
        @test content.type == "image"
        @test content.source.media_type == "image/png"
    end

    @testset "ToolUseContent Deserialization" begin
        json_str = """
        {
            "type": "tool_use",
            "id": "toolu_123",
            "name": "get_weather",
            "input": {
                "location": "San Francisco",
                "unit": "celsius"
            }
        }
        """

        parsed = JSON.parse(json_str, dicttype=Dict{Symbol,Any})
        content = StructTypes.constructfrom(ToolUseContent, parsed)

        @test content isa ToolUseContent
        @test content.type == "tool_use"
        @test content.id == "toolu_123"
        @test content.name == "get_weather"
        @test content.input[:location] == "San Francisco"
    end

    @testset "AbstractContent Polymorphic Deserialization" begin
        # text subtype
        text_content = StructTypes.constructfrom(AbstractContent,
            JSON.parse("""{"type": "text", "text": "Hello"}""", dicttype=Dict{Symbol,Any}))
        @test text_content isa TextContent

        # tool_use subtype
        tool_content = StructTypes.constructfrom(AbstractContent,
            JSON.parse("""{"type": "tool_use", "id": "t1", "name": "tool", "input": {}}""", dicttype=Dict{Symbol,Any}))
        @test tool_content isa ToolUseContent

        # image subtype
        image_content = StructTypes.constructfrom(AbstractContent,
            JSON.parse("""{"type": "image", "source": {"type": "base64", "media_type": "image/jpeg", "data": "abc123"}}""",
                dicttype=Dict{Symbol,Any}))
        @test image_content isa ImageContent
        @test image_content.source.media_type == "image/jpeg"

        # tool_result subtype
        result_content = StructTypes.constructfrom(AbstractContent,
            JSON.parse("""{"type": "tool_result", "tool_use_id": "t1", "content": "ok"}""",
                dicttype=Dict{Symbol,Any}))
        @test result_content isa ToolResultContent
    end

    @testset "MessageResponse Deserialization" begin
        json_str = """
        {
            "id": "msg_123abc",
            "type": "message",
            "role": "assistant",
            "content": [
                {
                    "type": "text",
                    "text": "Hello! How can I help you today?"
                }
            ],
            "model": "claude-sonnet-4-5-20250929",
            "stop_reason": "end_turn",
            "stop_sequence": null,
            "usage": {
                "input_tokens": 10,
                "output_tokens": 25
            }
        }
        """

        parsed = JSON.parse(json_str, dicttype=Dict{Symbol,Any})
        response = StructTypes.constructfrom(MessageResponse, parsed)

        @test response.id == "msg_123abc"
        @test response.type == "message"
        @test response.role == "assistant"
        @test length(response.content) == 1
        @test response.content[1] isa TextContent
        @test response.content[1].text == "Hello! How can I help you today?"
        @test response.model == "claude-sonnet-4-5-20250929"
        @test response.stop_reason == "end_turn"
        @test response.stop_sequence === nothing
        @test response.usage.input_tokens == 10
        @test response.usage.output_tokens == 25
    end

    @testset "Tool Construction from Dict" begin
        tool_dict = Dict{Symbol,Any}(
            :name => "get_weather",
            :description => "Get weather for a location",
            :input_schema => Dict{Symbol,Any}(
                :type => "object",
                :properties => Dict{String,Any}(
                    "location" => Dict{String,Any}(
                        "type" => "string",
                        "description" => "City name"
                    )
                ),
                :required => ["location"]
            )
        )

        tool = Tool(tool_dict)

        @test tool.name == "get_weather"
        @test tool.description == "Get weather for a location"
        @test tool.input_schema.type == "object"
        @test haskey(tool.input_schema.properties, "location")
        @test "location" in tool.input_schema.required
    end

    @testset "Usage Tracking" begin
        json_str = """{"input_tokens": 100, "output_tokens": 50}"""
        parsed = JSON.parse(json_str, dicttype=Dict{Symbol,Any})
        usage = StructTypes.constructfrom(Usage, parsed)

        @test usage.input_tokens == 100
        @test usage.output_tokens == 50
        @test total_tokens(usage) == 150
    end

    @testset "CountTokensResponse" begin
        json_str = """{"input_tokens": 42}"""
        parsed = JSON.parse(json_str, dicttype=Dict{Symbol,Any})
        response = StructTypes.constructfrom(CountTokensResponse, parsed)

        @test response.input_tokens == 42
    end

    @testset "AnthropicError" begin
        err = AnthropicError(429, "Rate limit exceeded", "rate_limit_error")
        @test err.status == 429
        @test err.message == "Rate limit exceeded"
        @test err.type == "rate_limit_error"
        @test err isa Exception

        buf = IOBuffer()
        Base.showerror(buf, err)
        msg = String(take!(buf))
        @test occursin("429", msg)
        @test occursin("rate_limit_error", msg)
        @test occursin("Rate limit exceeded", msg)
    end

    @testset "ToolResultContent Deserialization" begin
        json_str = """
        {
            "type": "tool_result",
            "tool_use_id": "toolu_abc",
            "content": "The weather is 72°F"
        }
        """
        parsed = JSON.parse(json_str, dicttype=Dict{Symbol,Any})
        content = StructTypes.constructfrom(ToolResultContent, parsed)
        @test content isa ToolResultContent
        @test content.type == "tool_result"
        @test content.tool_use_id == "toolu_abc"
        @test content.content == "The weather is 72°F"

        # AbstractContent polymorphic dispatch for tool_result
        result = StructTypes.constructfrom(AbstractContent, parsed)
        @test result isa ToolResultContent
    end

    @testset "Anthropic Client Construction" begin
        # Explicit API key
        client = Anthropic(api_key="sk-test-key")
        @test client.api_key == "sk-test-key"
        @test client.api_version == "2023-06-01"
        @test client.messages isa AnthropicSDK.Messages

        # Custom API version
        client2 = Anthropic(api_key="sk-test-key", api_version="2024-01-01")
        @test client2.api_version == "2024-01-01"

        # Missing API key with no env var set
        old_key = get(ENV, "ANTHROPIC_API_KEY", nothing)
        delete!(ENV, "ANTHROPIC_API_KEY")
        @test_throws ErrorException Anthropic()
        # Restore env
        isnothing(old_key) || (ENV["ANTHROPIC_API_KEY"] = old_key)

        # API key from environment variable
        ENV["ANTHROPIC_API_KEY"] = "sk-env-key"
        client3 = Anthropic()
        @test client3.api_key == "sk-env-key"
        delete!(ENV, "ANTHROPIC_API_KEY")
        isnothing(old_key) || (ENV["ANTHROPIC_API_KEY"] = old_key)
    end

    @testset "Streaming Event Types" begin
        # ContentBlockDelta
        delta_dict = Dict{String, Any}("type" => "text_delta", "text" => "Hello")
        delta_event = ContentBlockDelta("content_block_delta", 0, delta_dict)
        @test delta_event.type == "content_block_delta"
        @test delta_event.index == 0
        @test delta_event.delta["type"] == "text_delta"
        @test delta_event.delta["text"] == "Hello"

        # ContentBlockStart
        block_dict = Dict{String, Any}("type" => "text", "text" => "")
        start_event = ContentBlockStart("content_block_start", 0, block_dict)
        @test start_event.type == "content_block_start"
        @test start_event.content_block["type"] == "text"

        # ContentBlockStop
        stop_event = ContentBlockStop("content_block_stop", 0)
        @test stop_event.type == "content_block_stop"
        @test stop_event.index == 0

        # MessageStop
        msg_stop = MessageStop("message_stop")
        @test msg_stop.type == "message_stop"

        # PingEvent
        ping = PingEvent("ping")
        @test ping.type == "ping"

        # MessageDelta with Usage
        delta_d = Dict{String, Any}("stop_reason" => "end_turn")
        msg_delta = MessageDelta("message_delta", delta_d, Usage(10, 5))
        @test msg_delta.type == "message_delta"
        @test msg_delta.usage isa Usage
        @test msg_delta.usage.output_tokens == 5
        @test total_tokens(msg_delta.usage) == 15

        # MessageStartEvent wraps a MessageResponse
        inner_usage = Usage(10, 0)
        inner_response = MessageResponse("msg_001", "message", "assistant",
            AbstractContent[], "claude-sonnet-4-6", nothing, nothing, inner_usage)
        start_msg = MessageStartEvent("message_start", inner_response)
        @test start_msg.type == "message_start"
        @test start_msg.message.id == "msg_001"
        @test start_msg.message.usage.input_tokens == 10
    end

    @testset "Message Construction" begin
        # Test that Message accepts AbstractString
        msg1 = Message("user", "Hello")
        @test msg1.role == "user"
        @test msg1.content == "Hello"

        # Test with vector of content
        content_blocks = AbstractContent[
            TextContent("text", "Hello, world!")
        ]
        msg2 = Message("assistant", content_blocks)
        @test msg2.role == "assistant"
        @test length(msg2.content) == 1
        @test msg2.content[1].text == "Hello, world!"
    end

    @testset "JSON Serialization" begin
        msg = Message("user", "Test message")
        json_str = JSON.json([msg])
        @test occursin("user", json_str)
        @test occursin("Test message", json_str)
        parsed_back = JSON.parse(json_str)
        @test parsed_back isa Vector
        @test parsed_back[1]["role"] == "user"
        @test parsed_back[1]["content"] == "Test message"

        tool = Tool(
            "test_tool",
            "A test tool",
            ToolInputSchema(
                Dict{String, Any}("param" => Dict("type" => "string", "description" => "A param")),
                ["param"]
            )
        )
        tool_json = JSON.json(tool)
        @test occursin("test_tool", tool_json)
        parsed_tool = JSON.parse(tool_json)
        @test parsed_tool["name"] == "test_tool"
        @test parsed_tool["description"] == "A test tool"
    end
end
