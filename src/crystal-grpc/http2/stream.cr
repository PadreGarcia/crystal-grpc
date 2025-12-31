# HTTP/2 Stream Management
# Implements stream state machine and flow control

module HTTP2
  # Stream states as per RFC 7540
  enum StreamState
    IDLE
    RESERVED_LOCAL
    RESERVED_REMOTE
    OPEN
    HALF_CLOSED_LOCAL
    HALF_CLOSED_REMOTE
    CLOSED
  end

  # Represents an HTTP/2 stream
  class Stream
    property id : UInt32
    property state : StreamState
    property window_size : Int32
    property headers : Hash(String, String)
    property data : IO::Memory
    property channel : Channel(Frame)

    def initialize(@id : UInt32)
      @state = StreamState::IDLE
      @window_size = 65535 # Default initial window size
      @headers = {} of String => String
      @data = IO::Memory.new
      @channel = Channel(Frame).new(100)
    end

    def open
      @state = StreamState::OPEN
    end

    def close
      @state = StreamState::CLOSED
    end

    def half_close_local
      @state = StreamState::HALF_CLOSED_LOCAL
    end

    def half_close_remote
      @state = StreamState::HALF_CLOSED_REMOTE
    end

    def closed? : Bool
      @state == StreamState::CLOSED
    end

    def open? : Bool
      @state == StreamState::OPEN
    end

    def add_data(data : Bytes)
      @data.write(data)
    end

    def get_data : Bytes
      @data.to_slice
    end

    def update_window(increment : Int32)
      @window_size += increment
    end
  end

  # Manages multiple HTTP/2 streams
  class StreamManager
    @streams : Hash(UInt32, Stream)
    @next_stream_id : UInt32
    @mutex : Mutex

    def initialize(is_client : Bool = true)
      @streams = {} of UInt32 => Stream
      @next_stream_id = is_client ? 1_u32 : 2_u32
      @mutex = Mutex.new
    end

    def create_stream : Stream
      @mutex.synchronize do
        stream_id = @next_stream_id
        @next_stream_id += 2
        stream = Stream.new(stream_id)
        @streams[stream_id] = stream
        stream
      end
    end

    def get_stream(stream_id : UInt32) : Stream?
      @mutex.synchronize do
        @streams[stream_id]?
      end
    end

    def get_or_create_stream(stream_id : UInt32) : Stream
      @mutex.synchronize do
        @streams[stream_id] ||= Stream.new(stream_id)
      end
    end

    def close_stream(stream_id : UInt32)
      @mutex.synchronize do
        if stream = @streams[stream_id]?
          stream.close
          @streams.delete(stream_id)
        end
      end
    end

    def has_stream?(stream_id : UInt32) : Bool
      @mutex.synchronize do
        @streams.has_key?(stream_id)
      end
    end

    def active_streams : Array(Stream)
      @mutex.synchronize do
        @streams.values.select(&.open?)
      end
    end

    def stream_count : Int32
      @mutex.synchronize do
        @streams.size
      end
    end
  end

  # HTTP/2 Connection settings
  class ConnectionSettings
    property header_table_size : UInt32 = 4096_u32
    property enable_push : Bool = true
    property max_concurrent_streams : UInt32 = 100_u32
    property initial_window_size : UInt32 = 65535_u32
    property max_frame_size : UInt32 = 16384_u32
    property max_header_list_size : UInt32 = 8192_u32

    def initialize
    end

    def to_hash : Hash(UInt16, UInt32)
      {
        0x1_u16 => @header_table_size,
        0x2_u16 => (@enable_push ? 1_u32 : 0_u32),
        0x3_u16 => @max_concurrent_streams,
        0x4_u16 => @initial_window_size,
        0x5_u16 => @max_frame_size,
        0x6_u16 => @max_header_list_size,
      }
    end

    def update_from_hash(settings : Hash(UInt16, UInt32))
      settings.each do |id, value|
        case id
        when 0x1
          @header_table_size = value
        when 0x2
          @enable_push = value != 0
        when 0x3
          @max_concurrent_streams = value
        when 0x4
          @initial_window_size = value
        when 0x5
          @max_frame_size = value
        when 0x6
          @max_header_list_size = value
        end
      end
    end
  end
end
