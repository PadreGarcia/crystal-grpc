# HTTP/2 Connection Handler
# Manages HTTP/2 connection lifecycle and frame processing

require "./frame"
require "./hpack"
require "./stream"

module HTTP2
  # HTTP/2 connection preface
  CONNECTION_PREFACE = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"

  class Connection
    property socket : IO
    property is_client : Bool
    property stream_manager : StreamManager
    property settings : ConnectionSettings
    property hpack_encoder : HPACK::Encoder
    property hpack_decoder : HPACK::Decoder
    property closed : Bool

    def initialize(@socket : IO, @is_client : Bool = false)
      @stream_manager = StreamManager.new(@is_client)
      @settings = ConnectionSettings.new
      @hpack_encoder = HPACK::Encoder.new
      @hpack_decoder = HPACK::Decoder.new
      @closed = false
    end

    # Send the HTTP/2 connection preface (client only)
    def send_preface
      return unless @is_client
      @socket.write(CONNECTION_PREFACE.to_slice)
    end

    # Read and validate connection preface (server only)
    def read_preface
      return if @is_client
      
      buffer = Bytes.new(CONNECTION_PREFACE.bytesize)
      @socket.read_fully(buffer)
      
      if String.new(buffer) != CONNECTION_PREFACE
        raise "Invalid HTTP/2 connection preface"
      end
    end

    # Send a frame
    def send_frame(frame : Frame)
      raise "Connection closed" if @closed
      @socket.write(frame.to_bytes)
      @socket.flush
    end

    # Read a frame from the connection
    def read_frame : Frame?
      return nil if @closed
      
      # Read frame header (9 bytes)
      header = Bytes.new(9)
      bytes_read = @socket.read(header)
      return nil if bytes_read == 0
      
      raise "Incomplete frame header" if bytes_read < 9
      
      # Parse length
      length = (header[0].to_u32 << 16) | (header[1].to_u32 << 8) | header[2].to_u32
      
      # Read frame payload
      payload = Bytes.new(length)
      if length > 0
        @socket.read_fully(payload)
      end
      
      # Combine header and payload
      full_frame = Bytes.new(9 + length)
      header.copy_to(full_frame)
      payload.copy_to(full_frame + 9) if length > 0
      
      Frame.parse(full_frame)
    rescue IO::Error
      nil
    end

    # Send SETTINGS frame
    def send_settings(ack : Bool = false)
      settings = @settings.to_hash
      frame = SettingsFrame.new(settings, ack)
      send_frame(frame)
    end

    # Send HEADERS frame
    def send_headers(stream_id : UInt32, headers : Hash(String, String), end_stream : Bool = false, end_headers : Bool = true)
      header_block = @hpack_encoder.encode(headers)
      frame = HeadersFrame.new(stream_id, header_block, end_headers, end_stream)
      send_frame(frame)
    end

    # Send DATA frame
    def send_data(stream_id : UInt32, data : Bytes, end_stream : Bool = false)
      frame = DataFrame.new(stream_id, data, end_stream)
      send_frame(frame)
    end

    # Send PING frame
    def send_ping(opaque_data : Bytes = Bytes.new(8, 0_u8), ack : Bool = false)
      frame = PingFrame.new(opaque_data, ack)
      send_frame(frame)
    end

    # Send GOAWAY frame
    def send_goaway(last_stream_id : UInt32 = 0_u32, error_code : UInt32 = 0_u32, debug_data : String = "")
      frame = GoAwayFrame.new(last_stream_id, error_code, debug_data.to_slice)
      send_frame(frame)
      @closed = true
    end

    # Send WINDOW_UPDATE frame
    def send_window_update(stream_id : UInt32, increment : UInt32)
      frame = WindowUpdateFrame.new(stream_id, increment)
      send_frame(frame)
    end

    # Send RST_STREAM frame
    def send_rst_stream(stream_id : UInt32, error_code : UInt32)
      frame = RstStreamFrame.new(stream_id, error_code)
      send_frame(frame)
    end

    # Process received frame
    def process_frame(frame : Frame, &block : Frame ->)
      case frame.type
      when FrameType::SETTINGS
        if frame.has_flag?(FrameFlags::ACK)
          # Settings acknowledged
        else
          settings = SettingsFrame.parse_settings(frame.payload)
          @settings.update_from_hash(settings)
          # Send ACK
          send_settings(ack: true)
        end
      when FrameType::PING
        if !frame.has_flag?(FrameFlags::ACK)
          # Reply with PING ACK
          send_ping(frame.payload, ack: true)
        end
      when FrameType::GOAWAY
        @closed = true
      when FrameType::WINDOW_UPDATE
        if frame.stream_id == 0
          # Connection-level window update
        else
          # Stream-level window update
          stream = @stream_manager.get_stream(frame.stream_id)
          if stream
            increment = IO::ByteFormat::BigEndian.decode(UInt32, frame.payload)
            stream.update_window(increment.to_i32)
          end
        end
      when FrameType::RST_STREAM
        @stream_manager.close_stream(frame.stream_id)
      else
        # Pass frame to handler
        yield frame
      end
    end

    # Close the connection
    def close
      unless @closed
        send_goaway
      end
      @socket.close rescue nil
    end
  end
end
