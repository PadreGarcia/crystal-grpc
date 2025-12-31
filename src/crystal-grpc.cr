# Crystal gRPC - Pure Crystal implementation of gRPC
# No wrappers, no bindings, no external gRPC runtime
# Built from scratch with HTTP/2 and Protocol Buffers

require "./crystal-grpc/protobuf/wire"
require "./crystal-grpc/http2/frame"
require "./crystal-grpc/http2/hpack"
require "./crystal-grpc/http2/stream"
require "./crystal-grpc/http2/connection"
require "./crystal-grpc/grpc/protocol"
require "./crystal-grpc/grpc/server"
require "./crystal-grpc/grpc/client"

module CrystalGRPC
  VERSION = "0.1.0"

  # Convenience method to create a server
  def self.create_server(host : String = "0.0.0.0", port : Int32 = 50051) : GRPC::Server
    GRPC::Server.new(host, port)
  end

  # Convenience method to create a client
  def self.create_client(host : String = "localhost", port : Int32 = 50051) : GRPC::Client
    GRPC::Client.new(host, port)
  end

  # Convenience method to create a channel
  def self.create_channel(host : String = "localhost", port : Int32 = 50051) : GRPC::ClientChannel
    GRPC::ClientChannel.new(host, port)
  end
end

# Export main modules
module Protobuf
end

module HTTP2
end

module GRPC
end
