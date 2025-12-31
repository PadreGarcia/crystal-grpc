# Example gRPC Server - Echo Service
# Demonstrates a simple unary RPC implementation

require "../src/crystal-grpc"

# Create a simple Echo service using Protocol Buffers
# Message format: EchoRequest { string message = 1; }
# Message format: EchoResponse { string message = 1; }

def encode_echo_request(message : String) : Bytes
  builder = Protobuf::MessageBuilder.new
  builder.add_string(1_u32, message)
  builder.to_bytes
end

def decode_echo_request(data : Bytes) : String
  reader = Protobuf::MessageReader.new(data)
  
  while field = reader.read_field
    field_number, wire_type, field_data = field
    if field_number == 1 && wire_type == Protobuf::WireType::LENGTH_DELIMITED
      return String.new(field_data)
    end
  end
  
  ""
end

def encode_echo_response(message : String) : Bytes
  builder = Protobuf::MessageBuilder.new
  builder.add_string(1_u32, message)
  builder.to_bytes
end

# Create and configure the server
server = CrystalGRPC.create_server("0.0.0.0", 50051)

# Register the Echo service
server.register_service("echo.Echo")

# Register the SayHello method
server.register_method("echo.Echo", "SayHello") do |request_data|
  # Decode request
  message = decode_echo_request(request_data)
  puts "Received: #{message}"
  
  # Create response
  response_message = "Hello, #{message}!"
  encode_echo_response(response_message)
end

# Register the Echo method (simple echo)
server.register_method("echo.Echo", "Echo") do |request_data|
  # Decode request
  message = decode_echo_request(request_data)
  puts "Echo: #{message}"
  
  # Echo back the same message
  encode_echo_response(message)
end

puts "Starting Echo gRPC server on port 50051..."
puts "Available methods:"
puts "  - /echo.Echo/SayHello"
puts "  - /echo.Echo/Echo"
puts ""

# Start the server (blocking)
server.start
