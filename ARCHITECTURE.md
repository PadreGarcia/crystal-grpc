# Architecture Guide for Crystal gRPC

## Overview

This is a complete gRPC implementation built from scratch in pure Crystal, with no external dependencies or bindings. The implementation consists of three main layers:

## Layer 1: Protocol Buffers (`src/crystal-grpc/protobuf/`)

### Wire Format
Protocol Buffers uses a binary wire format with the following wire types:
- **VARINT** (0): For int32, int64, uint32, uint64, sint32, sint64, bool, enum
- **FIXED64** (1): For fixed64, sfixed64, double
- **LENGTH_DELIMITED** (2): For string, bytes, embedded messages, repeated fields
- **FIXED32** (5): For fixed32, sfixed32, float

### Key Components

**Varint Encoding**
```crystal
# Variable-length integer encoding
# Uses 7 bits per byte, MSB indicates continuation
value = 300
# Encoded as: [0xAC, 0x02]
# 10101100 00000010
```

**MessageBuilder**
```crystal
builder = Protobuf::MessageBuilder.new
builder.add_varint(1_u32, 42_u64)      # Field 1: integer value 42
builder.add_string(2_u32, "hello")     # Field 2: string "hello"
builder.add_bytes(3_u32, data)         # Field 3: raw bytes
message = builder.to_bytes
```

**MessageReader**
```crystal
reader = Protobuf::MessageReader.new(message)
while field = reader.read_field
  field_number, wire_type, data = field
  case field_number
  when 1
    value, _ = Protobuf.decode_varint(data)
  when 2
    text = String.new(data)
  end
end
```

## Layer 2: HTTP/2 (`src/crystal-grpc/http2/`)

### Frame Structure
Every HTTP/2 frame has a 9-byte header:
```
+-----------------------------------------------+
|                 Length (24)                   |
+---------------+---------------+---------------+
|   Type (8)    |   Flags (8)   |
+-+-------------+---------------+-------------------------------+
|R|                 Stream Identifier (31)                      |
+=+=============================================================+
|                   Frame Payload (0...)                      ...
+---------------------------------------------------------------+
```

### Key Components

**Frame Types**
- **DATA**: Carries application data for a stream
- **HEADERS**: Carries HTTP headers (compressed with HPACK)
- **SETTINGS**: Connection-level configuration
- **PING**: Connectivity check
- **GOAWAY**: Graceful connection shutdown
- **WINDOW_UPDATE**: Flow control
- **RST_STREAM**: Abort a stream

**HPACK Header Compression**
```crystal
# Encoding
encoder = HTTP2::HPACK::Encoder.new
encoded = encoder.encode({
  ":method" => "POST",
  ":path" => "/service/method",
  "content-type" => "application/grpc"
})

# Decoding
decoder = HTTP2::HPACK::Decoder.new
headers = decoder.decode(encoded)
```

**Stream Management**
```crystal
manager = HTTP2::StreamManager.new(is_client: true)
stream = manager.create_stream
stream.id              # Stream ID (odd for client, even for server)
stream.state           # IDLE, OPEN, HALF_CLOSED_LOCAL, etc.
stream.window_size     # Flow control window
```

**Connection**
```crystal
connection = HTTP2::Connection.new(socket, is_client: true)
connection.send_preface           # Client only
connection.send_settings          # Exchange settings
connection.send_headers(stream_id, headers)
connection.send_data(stream_id, data, end_stream: true)
```

## Layer 3: gRPC (`src/crystal-grpc/grpc/`)

### Message Framing
gRPC messages are framed over HTTP/2 DATA frames:
```
+------------------+------------------+------------------+------------------+
| Compressed Flag  |    Message Length (4 bytes, big-endian)             |
|    (1 byte)      |                                                      |
+------------------+------------------------------------------------------+
|                                                                          |
|                        Protobuf Message Data                            |
|                                                                          |
+--------------------------------------------------------------------------+
```

### Key Components

**Server**
```crystal
server = GRPC::Server.new("0.0.0.0", 50051)

# Register service
server.register_service("my.Service")

# Register method handler
server.register_method("my.Service", "MyMethod") do |request_data|
  # Decode request
  reader = Protobuf::MessageReader.new(request_data)
  
  # Process...
  
  # Encode response
  builder = Protobuf::MessageBuilder.new
  builder.add_string(1_u32, "response")
  builder.to_bytes
end

server.start  # Blocking
```

**Client**
```crystal
client = GRPC::Client.new("localhost", 50051)
client.connect

# Build request
builder = Protobuf::MessageBuilder.new
builder.add_string(1_u32, "request")
request = builder.to_bytes

# Make call
response = client.unary_call(
  "my.Service",
  "MyMethod",
  request,
  timeout: 5.seconds
)

if response.ok?
  # Decode response
  reader = Protobuf::MessageReader.new(response.message)
end

client.close
```

**Status Codes**
```crystal
GRPC::Status.ok                    # Success
GRPC::Status.cancelled             # Operation cancelled
GRPC::Status.invalid_argument      # Invalid request
GRPC::Status.not_found             # Resource not found
GRPC::Status.internal              # Internal error
GRPC::Status.unimplemented         # Method not implemented
```

## Concurrency Model

### Fibers
Crystal uses lightweight fibers (green threads) for concurrency:

```crystal
# Server handles each connection in a separate fiber
spawn handle_connection(socket)

# Client processes frames in background fiber
spawn process_frames
```

### Channels
Used for communication between fibers:

```crystal
# Stream has a channel for receiving frames
stream.channel.send(frame)
frame = stream.channel.receive
```

### Non-blocking I/O
All socket operations are non-blocking:

```crystal
socket.read(buffer)   # Non-blocking read
socket.write(data)    # Non-blocking write
```

## Request Flow

### Server Side
1. Accept TCP connection
2. Read HTTP/2 preface
3. Exchange SETTINGS frames
4. Receive HEADERS frame → create stream
5. Receive DATA frame → accumulate message
6. When END_STREAM flag set → decode gRPC message
7. Call registered handler
8. Encode response as gRPC message
9. Send HEADERS frame with status 200
10. Send DATA frame with response
11. Send HEADERS frame with trailers (grpc-status)

### Client Side
1. Connect TCP socket
2. Send HTTP/2 preface
3. Exchange SETTINGS frames
4. Create stream
5. Send HEADERS frame with method path
6. Encode and send gRPC message in DATA frame
7. Wait for response frames
8. Accumulate DATA frames
9. Parse trailers for grpc-status
10. Decode and return response

## Binary Operations

### Efficient Memory Management
```crystal
# Use IO::Memory for building binary data
io = IO::Memory.new
io.write_byte(0x42)
io.write_bytes(value, IO::ByteFormat::BigEndian)
result = io.to_slice  # Zero-copy conversion to Bytes

# Use Slice(UInt8) for binary data
data = Bytes.new(1024)
slice = data[offset, length]  # View into data, no copy
```

### Byte Order
- HTTP/2 uses **big-endian** for frame headers and integers
- Protocol Buffers uses **little-endian** for fixed32/fixed64

## Performance Considerations

1. **Zero-copy operations**: Use `Slice` views instead of copying data
2. **Fiber scheduling**: Crystal's event loop handles fiber scheduling efficiently
3. **Non-blocking I/O**: Prevents blocking the event loop
4. **Connection pooling**: Client can maintain multiple connections
5. **Stream multiplexing**: Multiple RPCs over single TCP connection

## Testing

Run the test suite:
```bash
crystal spec
```

Individual tests:
```bash
crystal spec spec/crystal-grpc_spec.cr
```

## Debugging

Enable verbose output:
```crystal
# Add debug statements
puts "Frame type: #{frame.type}"
puts "Stream ID: #{stream.id}"
puts "Message size: #{message.size}"
```

Inspect binary data:
```crystal
# Hex dump
data.hexdump
```

## Limitations

Current implementation supports:
- ✅ Unary RPC (request → response)
- ✅ Protocol Buffers wire format
- ✅ HTTP/2 framing and multiplexing
- ✅ HPACK header compression
- ⏳ Streaming RPC (future)
- ⏳ Compression (future)
- ⏳ TLS/SSL (future)

## References

- [gRPC Protocol](https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md)
- [HTTP/2 RFC 7540](https://tools.ietf.org/html/rfc7540)
- [HPACK RFC 7541](https://tools.ietf.org/html/rfc7541)
- [Protocol Buffers Encoding](https://developers.google.com/protocol-buffers/docs/encoding)
