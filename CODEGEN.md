# Code Generator Usage Guide

## Overview

The `protoc-gen-crystal` code generator reads Protocol Buffer FileDescriptorSet from stdin and generates strongly-typed Crystal client and server stubs.

## Features

- **Strong typing only** - All generated code uses Crystal's type system
- **No macros** - Pure Crystal code without metaprogramming
- **Idiomatic Crystal** - Follows Crystal naming conventions and style
- **Unary RPC support** - Generates client stubs and server interfaces

## Installation

Build the generator:

```bash
crystal build bin/protoc-gen-crystal -o bin/protoc-gen-crystal
```

Or use via shards:

```bash
shards build protoc-gen-crystal
```

## Usage

### Step 1: Create a .proto file

```protobuf
syntax = "proto3";

package example;

message HelloRequest {
  string name = 1;
}

message HelloResponse {
  string message = 1;
}

service Greeter {
  rpc SayHello (HelloRequest) returns (HelloResponse);
}
```

### Step 2: Generate FileDescriptorSet

Use `protoc` to generate a FileDescriptorSet:

```bash
protoc --descriptor_set_out=/dev/stdout --include_imports example.proto | \
  ./bin/protoc-gen-crystal > generated.cr
```

Or save to a file first:

```bash
protoc --descriptor_set_out=descriptor.pb --include_imports example.proto
cat descriptor.pb | ./bin/protoc-gen-crystal > generated.cr
```

### Step 3: Use generated code

#### Server implementation:

```crystal
require "./generated"

class MyGreeter < GreeterService
  def say_hello(request : HelloRequest) : HelloResponse
    HelloResponse.new(
      message: "Hello, #{request.name}!"
    )
  end
end

server = GRPC::Server.new("0.0.0.0", 50051)
service = MyGreeter.new
register_greeter_service(server, service)
server.start
```

#### Client usage:

```crystal
require "./generated"

client = GreeterClient.new("localhost", 50051)

request = HelloRequest.new(name: "World")
response = client.say_hello(request, timeout: 5.seconds)
puts response.message  # => "Hello, World!"

client.close
```

## Generated Code Structure

For each `.proto` file, the generator creates:

### Messages

Each message becomes a Crystal class with:
- Typed properties for all fields
- Constructor with default values
- `encode` method to serialize to bytes
- `decode` class method to deserialize from bytes

Example:
```crystal
class HelloRequest
  property name : String

  def initialize(@name : String)
  end

  def encode : Bytes
    # Protobuf encoding logic
  end

  def self.decode(data : Bytes) : HelloRequest
    # Protobuf decoding logic
  end
end
```

### Services

For each service, generates:

1. **Client stub** - `ServiceNameClient` class with methods for each RPC
2. **Server interface** - Abstract `ServiceNameService` class
3. **Registration helper** - Function to register service with gRPC server

## Type Mapping

Protocol Buffers types map to Crystal types:

| Proto Type | Crystal Type |
|------------|--------------|
| double     | Float64      |
| float      | Float32      |
| int32      | Int32        |
| int64      | Int64        |
| uint32     | UInt32       |
| uint64     | UInt64       |
| bool       | Bool         |
| string     | String       |
| bytes      | Bytes        |
| message    | MessageType  |

Repeated fields become `Array(T)`, optional fields become `T?`.

## Limitations

Current version supports:
- ✅ Unary RPC calls
- ✅ Basic scalar types
- ✅ String and bytes
- ✅ Nested messages
- ✅ Repeated fields
- ✅ Optional fields

Not yet supported:
- ⏳ Streaming RPCs (client, server, bidirectional)
- ⏳ Maps
- ⏳ Oneofs
- ⏳ Enums
- ⏳ Default values
- ⏳ Field options

## Advanced Usage

### Custom package names

The generator preserves package names from .proto files:

```protobuf
package my.company.api;
```

Generates service names like `my.company.api.ServiceName`.

### Multiple services

Generate code for multiple services in one file:

```bash
protoc --descriptor_set_out=/dev/stdout \
  --include_imports \
  service1.proto service2.proto | \
  ./bin/protoc-gen-crystal > generated.cr
```

### Integration with build systems

Add to your `Makefile`:

```makefile
generated.cr: example.proto
	protoc --descriptor_set_out=/dev/stdout --include_imports $< | \
		./bin/protoc-gen-crystal > $@

build: generated.cr
	crystal build src/main.cr
```

## Troubleshooting

**Error: No file descriptors found in input**
- Ensure you're using `--descriptor_set_out` flag with protoc
- Use `--include_imports` to include dependencies

**Type errors in generated code**
- Make sure all message types are defined in the .proto file
- Check that package names are consistent

**RPC method not found**
- Verify service and method names match the .proto definition
- Package names are case-sensitive

## Examples

See `examples/` directory for complete examples:
- `examples/generated_echo.proto` - Example protocol definition
- `examples/generated_server.cr` - Server using generated code
- `examples/generated_client.cr` - Client using generated code
