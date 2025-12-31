# Crystal gRPC

**A pure Crystal gRPC implementation built from scratch**

This is NOT a wrapper, NOT bindings, and NOT using external gRPC runtimes. Everything is implemented natively in Crystal Lang.

## Features

✅ **Pure Crystal Implementation**
- No C bindings or wrappers
- No external gRPC runtime dependencies
- Built entirely from scratch using Crystal 1.18.2

✅ **HTTP/2 Protocol**
- Full HTTP/2 framing implementation
- Stream multiplexing and management
- Flow control
- HPACK header compression
- Frame types: DATA, HEADERS, SETTINGS, PING, GOAWAY, WINDOW_UPDATE, RST_STREAM

✅ **Protocol Buffers**
- Wire format parser/serializer
- Varint encoding/decoding
- ZigZag encoding for signed integers
- Support for all wire types (varint, fixed64, length-delimited, fixed32)
- Message builder and reader utilities

✅ **gRPC Wire Protocol**
- gRPC message framing (compressed flag + length + message)
- Status codes (OK, CANCELLED, INVALID_ARGUMENT, etc.)
- Metadata handling
- Unary RPC calls

✅ **Concurrency & Performance**
- Fiber-based concurrency model
- Non-blocking I/O operations
- Channel-based communication
- Efficient binary operations with Slice(UInt8) and IO::Memory

✅ **Code Generator**
- Generate Crystal stubs from .proto files
- Strong typing (no macros)
- Idiomatic Crystal output
- Reads FileDescriptorSet from protoc

## Installation

Add this to your application's `shard.yml`:

```yaml
dependencies:
  crystal-grpc:
    github: PadreGarcia/crystal-grpc
```

Then run:

```bash
shards install
```

## Quick Start

### Server Example

```crystal
require "crystal-grpc"

# Create server
server = CrystalGRPC.create_server("0.0.0.0", 50051)

# Register service
server.register_service("echo.Echo")

# Register method handler
server.register_method("echo.Echo", "SayHello") do |request_data|
  # Decode request using Protocol Buffers
  reader = Protobuf::MessageReader.new(request_data)
  # ... process request ...
  
  # Encode response
  builder = Protobuf::MessageBuilder.new
  builder.add_string(1_u32, "Hello, World!")
  builder.to_bytes
end

# Start server
server.start
```

### Client Example

```crystal
require "crystal-grpc"

# Create and connect client
client = CrystalGRPC.create_client("localhost", 50051)
client.connect

# Encode request
builder = Protobuf::MessageBuilder.new
builder.add_string(1_u32, "World")
request = builder.to_bytes

# Make unary call
response = client.unary_call("echo.Echo", "SayHello", request, timeout: 5.seconds)

if response.ok?
  puts "Success: #{response.message}"
else
  puts "Error: #{response.status.message}"
end

client.close
```

## Architecture

### Components

1. **Protocol Buffers Layer** (`src/crystal-grpc/protobuf/`)
   - Wire format implementation
   - Varint encoding/decoding
   - Message builder and reader

2. **HTTP/2 Layer** (`src/crystal-grpc/http2/`)
   - Frame types and parsing
   - HPACK header compression
   - Stream management
   - Connection handling

3. **gRPC Layer** (`src/crystal-grpc/grpc/`)
   - gRPC wire protocol
   - Server implementation
   - Client implementation
   - Status codes and error handling

### Protocol Stack

```
┌─────────────────────────┐
│   Application Layer     │
├─────────────────────────┤
│   gRPC Protocol         │
│   - Message framing     │
│   - Status codes        │
│   - Metadata            │
├─────────────────────────┤
│   HTTP/2                │
│   - Frames              │
│   - Streams             │
│   - HPACK               │
├─────────────────────────┤
│   TCP Socket            │
│   - Non-blocking IO     │
└─────────────────────────┘
```

## Examples

### Manual API (examples/echo_server.cr)

Run the echo server:

```bash
crystal run examples/echo_server.cr
```

In another terminal, run the client:

```bash
crystal run examples/echo_client.cr
```

### Code Generator

Generate strongly-typed stubs from .proto files:

```bash
# Build the generator
shards build protoc-gen-crystal

# Generate code from .proto file
protoc --descriptor_set_out=/dev/stdout --include_imports example.proto | \
  ./bin/protoc-gen-crystal > generated.cr
```

See [CODEGEN.md](CODEGEN.md) for complete code generator documentation.

## API Documentation

### Server API

```crystal
# Create server
server = GRPC::Server.new(host: "0.0.0.0", port: 50051)

# Register service
server.register_service("my.Service")

# Register method
server.register_method("my.Service", "MyMethod") do |request_data : Bytes|
  # Return response as Bytes
  response_data
end

# Start server (blocking)
server.start
```

### Client API

```crystal
# Create client
client = GRPC::Client.new(host: "localhost", port: 50051)

# Connect
client.connect

# Make call
response = client.unary_call(
  service: "my.Service",
  method: "MyMethod",
  request: request_bytes,
  timeout: 5.seconds
)

# Check response
if response.ok?
  # Process response.message
else
  # Handle error: response.status.code, response.status.message
end

# Close
client.close
```

### Protocol Buffers API

```crystal
# Encoding
builder = Protobuf::MessageBuilder.new
builder.add_varint(1_u32, 42_u64)
builder.add_string(2_u32, "hello")
builder.add_bytes(3_u32, data)
message = builder.to_bytes

# Decoding
reader = Protobuf::MessageReader.new(message)
while field = reader.read_field
  field_number, wire_type, data = field
  # Process field
end
```

## Design Principles

1. **No External Dependencies**: Pure Crystal implementation without C bindings
2. **Non-blocking I/O**: All socket operations are non-blocking
3. **Fiber-based Concurrency**: Uses Crystal's lightweight fibers for concurrent request handling
4. **Efficient Binary Operations**: Uses Slice(UInt8) and IO::Memory for zero-copy operations
5. **RFC Compliance**: Implements HTTP/2 (RFC 7540), HPACK (RFC 7541), and gRPC specifications

## Supported Features

- ✅ Unary RPC calls
- ✅ Protocol Buffers serialization
- ✅ HTTP/2 framing and streams
- ✅ HPACK header compression
- ✅ gRPC status codes
- ✅ Metadata/headers
- ✅ Timeouts
- ⏳ Streaming RPC (planned)
- ⏳ Compression (planned)
- ⏳ TLS/SSL (planned)

## Requirements

- Crystal 1.18.2 or higher
- No external dependencies

## Testing

```bash
crystal spec
```

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## License

MIT License

## Credits

- Built for Crystal Lang 1.18.2
- Implements HTTP/2 (RFC 7540)
- Implements HPACK (RFC 7541)
- Follows gRPC protocol specifications

## Project Status

This is an educational and experimental implementation demonstrating how to build a complete gRPC library from scratch using only Crystal's standard library. It's suitable for learning purposes and simple use cases.