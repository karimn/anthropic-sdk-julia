using AnthropicSDK

# Initialize client
client = Anthropic()

println("=== Streaming Example ===\n")
println("Response: ")

# Stream a response
for event in stream(
    client.messages;
    model="claude-sonnet-4-5-20250929",
    max_tokens=1024,
    messages=[Message("user", "Write a haiku about Julia programming language")]
)
    # Check if this is a content delta event with text
    if haskey(event, :type) && event.type == "content_block_delta"
        if haskey(event, :delta) && haskey(event.delta, :text)
            print(event.delta.text)
        end
    end
end

println("\n")
