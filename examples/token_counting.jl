using AnthropicSDK

# Initialize client
client = Anthropic()

println("=== Token Counting Example ===\n")

messages = [
    Message("user", "Write a detailed explanation of how neural networks work, including backpropagation and gradient descent.")
]

# Count tokens before sending
token_count = count_tokens(
    client.messages;
    model="claude-sonnet-4-5-20250929",
    messages=messages
)

println("Input tokens (estimated): ", token_count.input_tokens)

# Now create the actual message
response = create(
    client.messages;
    model="claude-sonnet-4-5-20250929",
    max_tokens=2048,
    messages=messages
)

println("\nActual token usage:")
println("  Input tokens: ", response.usage.input_tokens)
println("  Output tokens: ", response.usage.output_tokens)
println("  Total tokens: ", response.usage.input_tokens + response.usage.output_tokens)

println("\nResponse preview (first 200 chars):")
println(response.content[1]["text"][1:min(200, length(response.content[1]["text"]))] * "...")
