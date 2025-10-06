using AnthropicSDK

# Initialize client
client = Anthropic()

println("=== Multi-turn Conversation Example ===\n")

# Build a conversation
conversation = [
    Message("user", "Hi! My name is Alice and I love programming in Julia."),
]

println("User: ", conversation[1].content)

# Get first response
response1 = create(
    client.messages;
    model="claude-sonnet-4-5-20250929",
    max_tokens=1024,
    messages=conversation
)

assistant_response1 = response1.content[1]["text"]
println("Assistant: ", assistant_response1)

# Add to conversation
push!(conversation, Message("assistant", assistant_response1))
push!(conversation, Message("user", "What programming language did I say I love?"))

println("\nUser: ", conversation[3].content)

# Get second response
response2 = create(
    client.messages;
    model="claude-sonnet-4-5-20250929",
    max_tokens=1024,
    messages=conversation
)

assistant_response2 = response2.content[1]["text"]
println("Assistant: ", assistant_response2)
