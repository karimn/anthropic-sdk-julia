using AnthropicSDK

# Initialize client
client = Anthropic()

println("=== Text Stream Example ===\n")
println("This demonstrates Julia's do-block syntax, equivalent to Python's 'with' statement.\n")

# Python equivalent:
# with client.messages.stream(
#     model=model,
#     max_tokens=1000,
#     messages=messages
# ) as stream:
#     for text in stream.text_stream:
#         print(text, end="")

# Julia version - Method 1: Using do-block with stream() (MOST PYTHONIC)
println("Method 1 - Do-block with stream() [Recommended - most like Python's with]:")
stream(client.messages;
    model="claude-sonnet-4-5-20250929",
    max_tokens=1024,
    messages=[Message("user", "Write a haiku about Julia programming")]
) do s
    for text in text_stream(s)
        print(text)
    end
end
println("\n")

# Julia version - Method 2: Using do-block with MessageStream()
println("\nMethod 2 - Do-block with MessageStream():")
MessageStream(client.messages;
    model="claude-sonnet-4-5-20250929",
    max_tokens=1024,
    messages=[Message("user", "Count to 5")]
) do s
    for text in text_stream(s)
        print(text)
    end
end
println("\n")

# Julia version - Method 3: Direct usage without do-block
println("\nMethod 3 - Direct usage (without do-block):")
s = MessageStream(
    client.messages;
    model="claude-sonnet-4-5-20250929",
    max_tokens=1024,
    messages=[Message("user", "What is 2+2?")]
)

for text in text_stream(s)
    print(text)
end
println("\n")

# Julia version - Method 4: Get all text at once
println("\nMethod 4 - get_final_text() [like Python's stream.get_final_text()]:")
s2 = MessageStream(
    client.messages;
    model="claude-sonnet-4-5-20250929",
    max_tokens=1024,
    messages=[Message("user", "Say hello")]
)

final_text = get_final_text(s2)
println(final_text)

println("\n=== Complete ===")
