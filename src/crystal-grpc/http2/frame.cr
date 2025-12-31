# HTTP/2 Frame Types and Parsing
# Implements HTTP/2 frame format as per RFC 7540

module HTTP2
  # Frame types as defined in RFC 7540
  enum FrameType : UInt8
    DATA          = 0x0
    HEADERS       = 0x1
    PRIORITY      = 0x2
    RST_STREAM    = 0x3
    SETTINGS      = 0x4
    PUSH_PROMISE  = 0x5
    PING          = 0x6
    GOAWAY        = 0x7
    WINDOW_UPDATE = 0x8
    CONTINUATION  = 0x9
  end

  # Frame flags
  @[Flags]
  enum FrameFlags : UInt8
    NONE         = 0x0
    END_STREAM   = 0x1
    END_HEADERS  = 0x4
    PADDED       = 0x8
    PRIORITY_FLAG = 0x20
    ACK          = 0x1
  end

  # HTTP/2 Frame structure
  class Frame
    property length : UInt32
    property type : FrameType
    property flags : UInt8
    property stream_id : UInt32
    property payload : Bytes

    def initialize(@length : UInt32, @type : FrameType, @flags : UInt8, @stream_id : UInt32, @payload : Bytes)
    end

    # Parse a frame from bytes
    def self.parse(data : Bytes) : Frame
      raise "Frame too short" if data.size < 9

      # Frame header is 9 bytes
      length = (data[0].to_u32 << 16) | (data[1].to_u32 << 8) | data[2].to_u32
      type = FrameType.new(data[3])
      flags = data[4]
      stream_id = ((data[5].to_u32 << 24) | (data[6].to_u32 << 16) | 
                   (data[7].to_u32 << 8) | data[8].to_u32) & 0x7FFFFFFF

      raise "Invalid frame length" if data.size < 9 + length

      payload = data[9, length]
      Frame.new(length, type, flags, stream_id, payload)
    end

    # Serialize frame to bytes
    def to_bytes : Bytes
      io = IO::Memory.new
      
      # Write length (24 bits)
      io.write_byte((@length >> 16).to_u8)
      io.write_byte((@length >> 8).to_u8)
      io.write_byte(@length.to_u8)
      
      # Write type
      io.write_byte(@type.value)
      
      # Write flags
      io.write_byte(@flags)
      
      # Write stream ID (31 bits, R bit is 0)
      io.write_byte((@stream_id >> 24).to_u8)
      io.write_byte((@stream_id >> 16).to_u8)
      io.write_byte((@stream_id >> 8).to_u8)
      io.write_byte(@stream_id.to_u8)
      
      # Write payload
      io.write(@payload)
      
      io.to_slice
    end

    def has_flag?(flag : FrameFlags) : Bool
      (@flags & flag.value) != 0
    end
  end

  # DATA frame
  class DataFrame < Frame
    def initialize(stream_id : UInt32, data : Bytes, end_stream : Bool = false)
      flags = end_stream ? FrameFlags::END_STREAM.value : 0_u8
      super(data.size.to_u32, FrameType::DATA, flags, stream_id, data)
    end
  end

  # HEADERS frame
  class HeadersFrame < Frame
    def initialize(stream_id : UInt32, header_block : Bytes, end_headers : Bool = true, end_stream : Bool = false)
      flags = 0_u8
      flags |= FrameFlags::END_HEADERS.value if end_headers
      flags |= FrameFlags::END_STREAM.value if end_stream
      super(header_block.size.to_u32, FrameType::HEADERS, flags, stream_id, header_block)
    end
  end

  # SETTINGS frame
  class SettingsFrame < Frame
    property settings : Hash(UInt16, UInt32)

    def initialize(@settings : Hash(UInt16, UInt32) = {} of UInt16 => UInt32, ack : Bool = false)
      payload = build_payload(@settings)
      flags = ack ? FrameFlags::ACK.value : 0_u8
      super(payload.size.to_u32, FrameType::SETTINGS, flags, 0_u32, payload)
    end

    private def build_payload(settings : Hash(UInt16, UInt32)) : Bytes
      io = IO::Memory.new
      settings.each do |id, value|
        io.write_bytes(id, IO::ByteFormat::BigEndian)
        io.write_bytes(value, IO::ByteFormat::BigEndian)
      end
      io.to_slice
    end

    def self.parse_settings(payload : Bytes) : Hash(UInt16, UInt32)
      settings = {} of UInt16 => UInt32
      offset = 0
      
      while offset < payload.size
        id = IO::ByteFormat::BigEndian.decode(UInt16, payload[offset, 2])
        value = IO::ByteFormat::BigEndian.decode(UInt32, payload[offset + 2, 4])
        settings[id] = value
        offset += 6
      end
      
      settings
    end
  end

  # PING frame
  class PingFrame < Frame
    def initialize(opaque_data : Bytes = Bytes.new(8, 0_u8), ack : Bool = false)
      raise "Ping data must be 8 bytes" if opaque_data.size != 8
      flags = ack ? FrameFlags::ACK.value : 0_u8
      super(8_u32, FrameType::PING, flags, 0_u32, opaque_data)
    end
  end

  # GOAWAY frame
  class GoAwayFrame < Frame
    property last_stream_id : UInt32
    property error_code : UInt32
    property debug_data : Bytes

    def initialize(@last_stream_id : UInt32, @error_code : UInt32, @debug_data : Bytes = Bytes.empty)
      payload = build_payload
      super(payload.size.to_u32, FrameType::GOAWAY, 0_u8, 0_u32, payload)
    end

    private def build_payload : Bytes
      io = IO::Memory.new
      io.write_bytes(@last_stream_id, IO::ByteFormat::BigEndian)
      io.write_bytes(@error_code, IO::ByteFormat::BigEndian)
      io.write(@debug_data)
      io.to_slice
    end
  end

  # WINDOW_UPDATE frame
  class WindowUpdateFrame < Frame
    def initialize(stream_id : UInt32, increment : UInt32)
      io = IO::Memory.new
      io.write_bytes(increment & 0x7FFFFFFF, IO::ByteFormat::BigEndian)
      payload = io.to_slice
      super(4_u32, FrameType::WINDOW_UPDATE, 0_u8, stream_id, payload)
    end
  end

  # RST_STREAM frame
  class RstStreamFrame < Frame
    def initialize(stream_id : UInt32, error_code : UInt32)
      io = IO::Memory.new
      io.write_bytes(error_code, IO::ByteFormat::BigEndian)
      payload = io.to_slice
      super(4_u32, FrameType::RST_STREAM, 0_u8, stream_id, payload)
    end
  end
end
