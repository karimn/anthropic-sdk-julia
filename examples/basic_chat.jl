using AnthropicSDK

# Initialize client (make sure ANTHROPIC_API_KEY is set)
client = Anthropic()

# Simple message
println("=== Basic Chat Example ===\n")

response = create(
    client.messages;
    model="claude-sonnet-4-5-20250929",
    max_tokens=1024,
    messages=[Message("user", "What is the capital of France? Answer in one sentence.")]
)

println("Response: ", response.content[1]["text"])
println("\nTokens used:")
println("  Input: ", response.usage.input_tokens)
println("  Output: ", response.usage.output_tokens)
println("  Total: ", +(response.usage))
