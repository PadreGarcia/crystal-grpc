# gRPC Client Implementation
# Non-blocking client with HTTP/2 connection support

require "socket"
require "../http2/connection"
require "../http2/frame"
require "./protocol"

module GRPC
  class Client
    property host : String
    property port : Int32
    property connection : HTTP2::Connection?
    property socket : TCPSocket?

    def initialize(@host : String = "localhost", @port : Int32 = 50051)
      @connection = nil
      @socket = nil
    end

    # Connect to the server
    def connect
      @socket = TCPSocket.new(@host, @port)
      @connection = HTTP2::Connection.new(@socket.not_nil!, is_client: true)
      
      # Send HTTP/2 preface
      @connection.not_nil!.send_preface
      
      # Send initial SETTINGS frame
      @connection.not_nil!.send_settings
      
      # Start frame processor in background
      spawn process_frames
    end

    # Close the connection
    def close
      @connection.try &.close
      @socket.try &.close
    end

    # Make a unary RPC call
    def unary_call(service : String, method : String, request : Bytes, timeout : Time::Span? = nil) : Response
      conn = @connection
      raise "Not connected" unless conn
      
      # Create a new stream
      stream = conn.stream_manager.create_stream
      stream_id = stream.id
      
      begin
        # Build request headers
        headers = {
          ":method"      => "POST",
          ":scheme"      => "http",
          ":path"        => "/#{service}/#{method}",
          ":authority"   => "#{@host}:#{@port}",
          "content-type" => "application/grpc",
          "te"           => "trailers",
        }
        
        # Add timeout if specified
        if timeout
          timeout_str = format_timeout(timeout)
          headers["grpc-timeout"] = timeout_str
        end
        
        # Send headers
        conn.send_headers(stream_id, headers, end_stream: false)
        
        # Encode and send gRPC message
        grpc_message = GRPC.encode_message(request)
        conn.send_data(stream_id, grpc_message, end_stream: true)
        
        # Wait for response
        response_channel = Channel(Response).new(1)
        
        spawn do
          response = wait_for_response(conn, stream)
          response_channel.send(response)
        end
        
        # Wait for response with optional timeout
        if timeout
          select
          when response = response_channel.receive
            response
          when timeout(timeout)
            conn.send_rst_stream(stream_id, 8_u32) # CANCEL
            Response.new(Bytes.empty, Status.cancelled("Request timeout"))
          end
        else
          response_channel.receive
        end
      ensure
        conn.stream_manager.close_stream(stream_id)
      end
    end

    # Wait for response on a stream
    private def wait_for_response(connection : HTTP2::Connection, stream : HTTP2::Stream) : Response
      status = Status.ok
      message = Bytes.empty
      
      # Wait for response frames
      loop do
        frame = stream.channel.receive?
        break unless frame
        
        case frame.type
        when HTTP2::FrameType::HEADERS
          headers = connection.hpack_decoder.decode(frame.payload)
          
          # Check for grpc-status in headers
          if grpc_status = headers["grpc-status"]?
            status_code = StatusCode.new(grpc_status.to_u32)
            status_message = headers["grpc-message"]? || ""
            status = Status.new(status_code, status_message)
          end
          
          # Check for END_STREAM
          break if frame.has_flag?(HTTP2::FrameFlags::END_STREAM)
        when HTTP2::FrameType::DATA
          stream.add_data(frame.payload)
          
          # Check for END_STREAM
          if frame.has_flag?(HTTP2::FrameFlags::END_STREAM)
            # Decode gRPC message
            data = stream.get_data
            if data.size >= 5
              compressed, msg = GRPC.decode_message(data)
              message = msg unless compressed
            end
            break
          end
        when HTTP2::FrameType::RST_STREAM
          status = Status.cancelled("Stream reset")
          break
        end
      end
      
      Response.new(message, status)
    end

    # Process incoming frames
    private def process_frames
      conn = @connection
      return unless conn
      
      while frame = conn.read_frame
        # Route frame to appropriate stream
        if frame.stream_id > 0
          stream = conn.stream_manager.get_stream(frame.stream_id)
          if stream
            stream.channel.send(frame)
          end
        end
        
        # Process connection-level frames
        conn.process_frame(frame) { }
      end
    rescue ex
      puts "Frame processing error: #{ex.message}"
    end

    # Format timeout for grpc-timeout header
    private def format_timeout(timeout : Time::Span) : String
      total_ms = timeout.total_milliseconds.to_i64
      
      if total_ms < 1000
        "#{total_ms}m"
      elsif total_ms < 60_000
        "#{total_ms // 1000}S"
      elsif total_ms < 3_600_000
        "#{total_ms // 60_000}M"
      else
        "#{total_ms // 3_600_000}H"
      end
    end
  end

  # Channel abstraction for client connections
  class ClientChannel
    property client : Client

    def initialize(host : String = "localhost", port : Int32 = 50051)
      @client = Client.new(host, port)
    end

    def connect
      @client.connect
    end

    def close
      @client.close
    end

    def call(service : String, method : String, request : Bytes, timeout : Time::Span? = nil) : Response
      @client.unary_call(service, method, request, timeout)
    end
  end
end
