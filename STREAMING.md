# Streaming Guide: Python to Julia Translation

## Python's `with` Statement → Julia's `do` Block

### Python Version
```python
with client.messages.stream(
    model=model,
    max_tokens=1000,
    messages=messages
) as stream:
    for text in stream.text_stream:
        print(text, end="")
```

### Julia Version (Recommended)
```julia
stream(client.messages;
    model=model,
    max_tokens=1000,
    messages=messages
) do s
    for text in text_stream(s)
        print(text)
    end
end
```

## All Available Methods

### 1. Do-block with `stream()` (Most Pythonic)
```julia
stream(client.messages; model="...", max_tokens=1000, messages=msgs) do s
    for text in text_stream(s)
        print(text)
    end
end
```

### 2. Do-block with `MessageStream()`
```julia
MessageStream(client.messages; model="...", max_tokens=1000, messages=msgs) do s
    for text in text_stream(s)
        print(text)
    end
end
```

### 3. Direct Usage (Without do-block)
```julia
s = MessageStream(client.messages; model="...", max_tokens=1000, messages=msgs)
for text in text_stream(s)
    print(text)
end
```

### 4. Get Final Text (Like Python's `stream.get_final_text()`)
```julia
s = MessageStream(client.messages; model="...", max_tokens=1000, messages=msgs)
final_text = get_final_text(s)
println(final_text)
```

### 5. Raw Event Streaming
```julia
for event in stream(client.messages; model="...", max_tokens=1000, messages=msgs)
    if event isa ContentBlockDelta && haskey(event.delta, :text)
        print(event.delta.text)
    end
end
```

## Key Differences

| Python | Julia | Notes |
|--------|-------|-------|
| `with ... as stream:` | `... do s` | Julia's do-block provides the same resource management |
| `stream.text_stream` | `text_stream(s)` | Function call instead of property |
| `stream.get_final_text()` | `get_final_text(s)` | Same concept, different syntax |
| `print(text, end="")` | `print(text)` | Julia's `print` doesn't add newlines by default |

## Event Types

All streaming events are automatically wrapped in typed structs with pretty printing:

- `MessageStartEvent` - Initial message metadata
- `ContentBlockStart` - New content block begins
- `ContentBlockDelta` - Incremental content (contains text)
- `ContentBlockStop` - Content block complete
- `MessageDelta` - Message-level updates
- `MessageStop` - Stream complete
- `PingEvent` - Keep-alive ping

Events display nicely when printed:
```julia
MessageStartEvent(message=msg_123)
ContentBlockDelta(index=0, delta=text_delta("Hello"))
ContentBlockStop(index=0)
```
