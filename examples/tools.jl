using AnthropicSDK

# Initialize client
client = Anthropic()

println("=== Tool Use Example ===\n")

# Define a weather tool
tools = [
    Tool(
        "get_weather",
        "Get the current weather for a location",
        ToolInputSchema(
            Dict(
                "location" => Dict(
                    "type" => "string",
                    "description" => "The city and state, e.g. San Francisco, CA"
                ),
                "unit" => Dict(
                    "type" => "string",
                    "enum" => ["celsius", "fahrenheit"],
                    "description" => "Temperature unit"
                )
            ),
            ["location"]
        )
    )
]

response = create(
    client.messages;
    model="claude-sonnet-4-5-20250929",
    max_tokens=1024,
    messages=[Message("user", "What's the weather like in San Francisco?")],
    tools=tools
)

println("Claude's response:")
for content in response.content
    if haskey(content, "type")
        if content["type"] == "text"
            println("  Text: ", content["text"])
        elseif content["type"] == "tool_use"
            println("  Tool Use:")
            println("    Name: ", content["name"])
            println("    Input: ", content["input"])

            # In a real application, you would:
            # 1. Execute the tool with the given input
            # 2. Send the result back to Claude
            # 3. Get Claude's final response
        end
    end
end

println("\nStop reason: ", response.stop_reason)
