# Example gRPC Client - Echo Service Client
# Demonstrates how to make unary RPC calls

require "../src/crystal-grpc"

# Helper functions for encoding/decoding messages
def encode_echo_request(message : String) : Bytes
  builder = Protobuf::MessageBuilder.new
  builder.add_string(1_u32, message)
  builder.to_bytes
end

def decode_echo_response(data : Bytes) : String
  reader = Protobuf::MessageReader.new(data)
  
  while field = reader.read_field
    field_number, wire_type, field_data = field
    if field_number == 1 && wire_type == Protobuf::WireType::LENGTH_DELIMITED
      return String.new(field_data)
    end
  end
  
  ""
end

# Create client
puts "Connecting to gRPC server at localhost:50051..."
client = CrystalGRPC.create_client("localhost", 50051)

begin
  # Connect to server
  client.connect
  puts "Connected!"
  
  # Give server time to send settings
  sleep 0.1
  
  # Make a SayHello call
  puts "\nCalling /echo.Echo/SayHello with 'World'..."
  request = encode_echo_request("World")
  response = client.unary_call("echo.Echo", "SayHello", request, timeout: 5.seconds)
  
  if response.ok?
    message = decode_echo_response(response.message)
    puts "Response: #{message}"
  else
    puts "Error: #{response.status.message} (code: #{response.status.code})"
  end
  
  # Make an Echo call
  puts "\nCalling /echo.Echo/Echo with 'Testing 1-2-3'..."
  request = encode_echo_request("Testing 1-2-3")
  response = client.unary_call("echo.Echo", "Echo", request, timeout: 5.seconds)
  
  if response.ok?
    message = decode_echo_response(response.message)
    puts "Response: #{message}"
  else
    puts "Error: #{response.status.message} (code: #{response.status.code})"
  end
  
  puts "\nAll calls completed successfully!"
rescue ex
  puts "Error: #{ex.message}"
  puts ex.backtrace.join("\n")
ensure
  # Close connection
  client.close
  puts "Connection closed."
end
