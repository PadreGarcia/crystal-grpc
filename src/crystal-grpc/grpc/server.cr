# gRPC Server Implementation
# Non-blocking TCP server with HTTP/2 and gRPC support

require "socket"
require "../http2/connection"
require "../http2/frame"
require "../http2/hpack"
require "./protocol"

module GRPC
  class Server
    property host : String
    property port : Int32
    property registry : ServiceRegistry
    property running : Bool

    def initialize(@host : String = "0.0.0.0", @port : Int32 = 50051)
      @registry = ServiceRegistry.new
      @running = false
    end

    # Register a service handler
    def register_service(service_name : String)
      @registry.register_service(service_name)
    end

    # Register a method handler
    def register_method(service_name : String, method_name : String, &handler : Bytes -> Bytes)
      @registry.register_method(service_name, method_name, handler)
    end

    # Register a method handler with proc
    def register_method(service_name : String, method_name : String, handler : UnaryHandler)
      @registry.register_method(service_name, method_name, handler)
    end

    # Start the server
    def start
      @running = true
      
      server = TCPServer.new(@host, @port)
      server.reuse_address = true
      
      puts "gRPC server listening on #{@host}:#{@port}"
      
      while @running
        socket = server.accept?
        break unless socket
        
        # Handle each connection in a separate fiber
        spawn handle_connection(socket)
      end
    rescue ex
      puts "Server error: #{ex.message}"
    ensure
      server.try &.close
    end

    # Stop the server
    def stop
      @running = false
    end

    # Handle a client connection
    private def handle_connection(socket : TCPSocket)
      connection = HTTP2::Connection.new(socket, is_client: false)
      
      # Read HTTP/2 preface
      connection.read_preface
      
      # Send initial SETTINGS frame
      connection.send_settings
      
      # Process frames
      while frame = connection.read_frame
        connection.process_frame(frame) do |f|
          handle_frame(connection, f)
        end
      end
    rescue ex
      puts "Connection error: #{ex.message}"
    ensure
      connection.try &.close
    end

    # Handle specific frame types
    private def handle_frame(connection : HTTP2::Connection, frame : HTTP2::Frame)
      case frame.type
      when HTTP2::FrameType::HEADERS
        handle_headers_frame(connection, frame)
      when HTTP2::FrameType::DATA
        handle_data_frame(connection, frame)
      end
    end

    # Handle HEADERS frame
    private def handle_headers_frame(connection : HTTP2::Connection, frame : HTTP2::Frame)
      stream_id = frame.stream_id
      stream = connection.stream_manager.get_or_create_stream(stream_id)
      
      # Decode headers
      headers = connection.hpack_decoder.decode(frame.payload)
      stream.headers = headers
      
      # Open the stream
      stream.open
      
      # If END_STREAM flag is set, process the request immediately
      if frame.has_flag?(HTTP2::FrameFlags::END_STREAM)
        process_request(connection, stream)
      end
    end

    # Handle DATA frame
    private def handle_data_frame(connection : HTTP2::Connection, frame : HTTP2::Frame)
      stream_id = frame.stream_id
      stream = connection.stream_manager.get_stream(stream_id)
      return unless stream
      
      # Accumulate data
      stream.add_data(frame.payload)
      
      # If END_STREAM flag is set, process the request
      if frame.has_flag?(HTTP2::FrameFlags::END_STREAM)
        process_request(connection, stream)
      end
    end

    # Process a complete gRPC request
    private def process_request(connection : HTTP2::Connection, stream : HTTP2::Stream)
      # Extract method from :path header
      path = stream.headers[":path"]?
      unless path
        send_error_response(connection, stream.id, Status.invalid_argument("Missing :path header"))
        return
      end
      
      # Find handler
      handler = @registry.find_handler(path)
      unless handler
        send_error_response(connection, stream.id, Status.unimplemented("Method not found: #{path}"))
        return
      end
      
      # Decode gRPC message
      data = stream.get_data
      if data.size < 5
        send_error_response(connection, stream.id, Status.invalid_argument("Invalid gRPC message"))
        return
      end
      
      compressed, message = GRPC.decode_message(data)
      
      # Handle compression (not implemented yet)
      if compressed
        send_error_response(connection, stream.id, Status.unimplemented("Compression not supported"))
        return
      end
      
      # Call handler
      begin
        response_message = handler.call(message)
        send_response(connection, stream.id, response_message, Status.ok)
      rescue ex
        send_error_response(connection, stream.id, Status.internal(ex.message || "Internal error"))
      end
      
      # Close stream
      connection.stream_manager.close_stream(stream.id)
    end

    # Send a successful response
    private def send_response(connection : HTTP2::Connection, stream_id : UInt32, message : Bytes, status : Status)
      # Send response headers
      response_headers = {
        ":status"      => "200",
        "content-type" => "application/grpc",
        "grpc-status"  => status.code.value.to_s,
      }
      
      connection.send_headers(stream_id, response_headers, end_stream: false)
      
      # Send response data
      grpc_message = GRPC.encode_message(message)
      connection.send_data(stream_id, grpc_message, end_stream: false)
      
      # Send trailers with grpc-status
      trailers = {
        "grpc-status"  => status.code.value.to_s,
        "grpc-message" => status.message,
      }
      
      connection.send_headers(stream_id, trailers, end_stream: true)
    end

    # Send an error response
    private def send_error_response(connection : HTTP2::Connection, stream_id : UInt32, status : Status)
      response_headers = {
        ":status"      => "200",
        "content-type" => "application/grpc",
        "grpc-status"  => status.code.value.to_s,
        "grpc-message" => status.message,
      }
      
      connection.send_headers(stream_id, response_headers, end_stream: true)
    end
  end
end
