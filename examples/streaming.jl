using AnthropicSDK

# Initialize client
client = Anthropic()

println("=== Streaming Example ===\n")

# Example 1: Show all events (with automatic pretty printing)
println("All events:")
for event in stream(
    client.messages;
    model="claude-sonnet-4-5-20250929",
    max_tokens=1024,
    messages=[Message("user", "Write a haiku about Julia programming language")]
)
    # Events are automatically wrapped in typed structs with custom show() methods
    # This will display events like:
    # MessageStartEvent(message=msg_123)
    # ContentBlockStart(index=0, content_block={...})
    # ContentBlockDelta(index=0, delta={...})
    # etc.
    println(event)
end

println("\n=== Text-only Output (Method 1: Manual filtering) ===\n")
println("Response: ")

# Example 2: Extract just the text content manually
for event in stream(
    client.messages;
    model="claude-sonnet-4-5-20250929",
    max_tokens=1024,
    messages=[Message("user", "Write a haiku about Julia programming language")]
)
    # Pattern match on event type
    if event isa ContentBlockDelta
        if haskey(event.delta, :text)
            print(event.delta.text)
        end
    end
end

println("\n")

println("\n=== Text-only Output (Method 2: Using MessageStream) ===\n")
println("Response: ")

# Example 3: Use MessageStream for easier text extraction (like Python's stream.text_stream)
# This is Julia's equivalent to:
# with client.messages.stream(...) as stream:
#     for text in stream.text_stream:
#         print(text, end="")

msg_stream = MessageStream(
    client.messages;
    model="claude-sonnet-4-5-20250929",
    max_tokens=1024,
    messages=[Message("user", "Write a haiku about Julia programming language")]
)

for text in text_stream(msg_stream)
    print(text)
end

println("\n")
