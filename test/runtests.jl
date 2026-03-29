using Test
using AnthropicSDK
using JSON
using StructTypes

@testset "AnthropicSDK.jl" begin

    @testset "JSON Migration - String Keys" begin
        # Test that JSON.parse returns string keys (not symbols like JSON3)
        json_str = """{"type": "text", "text": "hello"}"""
        parsed = JSON.parse(json_str)

        @test haskey(parsed, "type")
        @test !haskey(parsed, :type)  # Should NOT have symbol keys
        @test parsed["type"] == "text"
    end

    @testset "TextContent Deserialization" begin
        json_str = """
        {
            "type": "text",
            "text": "Hello, world!"
        }
        """

        parsed = JSON.parse(json_str)
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

        parsed = JSON.parse(json_str)
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

        parsed = JSON.parse(json_str)
        content = StructTypes.constructfrom(ToolUseContent, parsed)

        @test content isa ToolUseContent
        @test content.type == "tool_use"
        @test content.id == "toolu_123"
        @test content.name == "get_weather"
        @test content.input["location"] == "San Francisco"
    end

    @testset "AbstractContent Polymorphic Deserialization" begin
        # Test that StructTypes correctly discriminates based on "type" field
        text_json = """{"type": "text", "text": "Hello"}"""
        tool_json = """{"type": "tool_use", "id": "t1", "name": "tool", "input": {}}"""

        text_parsed = JSON.parse(text_json)
        tool_parsed = JSON.parse(tool_json)

        text_content = StructTypes.constructfrom(AbstractContent, text_parsed)
        tool_content = StructTypes.constructfrom(AbstractContent, tool_parsed)

        @test text_content isa TextContent
        @test tool_content isa ToolUseContent
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

        parsed = JSON.parse(json_str)
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
        tool_dict = Dict(
            "name" => "get_weather",
            "description" => "Get weather for a location",
            "input_schema" => Dict(
                "type" => "object",
                "properties" => Dict(
                    "location" => Dict(
                        "type" => "string",
                        "description" => "City name"
                    )
                ),
                "required" => ["location"]
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
        parsed = JSON.parse(json_str)
        usage = StructTypes.constructfrom(Usage, parsed)

        @test usage.input_tokens == 100
        @test usage.output_tokens == 50
        @test +(usage) == 150  # Test custom + operator
    end

    @testset "CountTokensResponse" begin
        json_str = """{"input_tokens": 42}"""
        parsed = JSON.parse(json_str)
        response = StructTypes.constructfrom(CountTokensResponse, parsed)

        @test response.input_tokens == 42
    end

    @testset "Streaming Event Types" begin
        # Test ContentBlockDelta with string keys (JSON.jl style)
        delta_dict = Dict("type" => "text_delta", "text" => "Hello")
        delta_event = ContentBlockDelta("content_block_delta", 0, delta_dict)

        @test delta_event.type == "content_block_delta"
        @test delta_event.index == 0
        @test delta_event.delta["type"] == "text_delta"
        @test delta_event.delta["text"] == "Hello"

        # Test ContentBlockStart
        block_dict = Dict("type" => "text", "text" => "")
        start_event = ContentBlockStart("content_block_start", 0, block_dict)

        @test start_event.type == "content_block_start"
        @test start_event.content_block["type"] == "text"
    end

    @testset "Message Construction" begin
        # Test that Message accepts AbstractString
        msg1 = Message("user", "Hello")
        @test msg1.role == "user"
        @test msg1.content == "Hello"

        # Test with vector of content
        content_blocks = [
            TextContent("text", "Hello, world!")
        ]
        msg2 = Message("assistant", content_blocks)
        @test msg2.role == "assistant"
        @test length(msg2.content) == 1
        @test msg2.content[1].text == "Hello, world!"
    end

    @testset "JSON Serialization" begin
        # Test that types can be serialized back to JSON
        msg = Message("user", "Test message")
        messages = [msg]

        json_str = JSON.json(messages)
        @test occursin("user", json_str)
        @test occursin("Test message", json_str)

        # Test tool serialization
        tool = Tool(
            "test_tool",
            "A test tool",
            ToolInputSchema(
                Dict("param" => Dict("type" => "string", "description" => "A param")),
                ["param"]
            )
        )

        json_str = JSON.json(tool)
        @test occursin("test_tool", json_str)
        @test occursin("A test tool", json_str)
    end
end
