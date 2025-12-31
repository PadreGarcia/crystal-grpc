# Simplified HPACK Implementation for HTTP/2 Header Compression
# RFC 7541

module HTTP2
  module HPACK
    # Static table entries (subset of RFC 7541 Appendix A)
    STATIC_TABLE = [
      {":authority", ""},
      {":method", "GET"},
      {":method", "POST"},
      {":path", "/"},
      {":path", "/index.html"},
      {":scheme", "http"},
      {":scheme", "https"},
      {":status", "200"},
      {":status", "204"},
      {":status", "206"},
      {":status", "304"},
      {":status", "400"},
      {":status", "404"},
      {":status", "500"},
      {"accept-charset", ""},
      {"accept-encoding", "gzip, deflate"},
      {"accept-language", ""},
      {"accept-ranges", ""},
      {"accept", ""},
      {"access-control-allow-origin", ""},
      {"age", ""},
      {"allow", ""},
      {"authorization", ""},
      {"cache-control", ""},
      {"content-disposition", ""},
      {"content-encoding", ""},
      {"content-language", ""},
      {"content-length", ""},
      {"content-location", ""},
      {"content-range", ""},
      {"content-type", ""},
      {"cookie", ""},
      {"date", ""},
      {"etag", ""},
      {"expect", ""},
      {"expires", ""},
      {"from", ""},
      {"host", ""},
      {"if-match", ""},
      {"if-modified-since", ""},
      {"if-none-match", ""},
      {"if-range", ""},
      {"if-unmodified-since", ""},
      {"last-modified", ""},
      {"link", ""},
      {"location", ""},
      {"max-forwards", ""},
      {"proxy-authenticate", ""},
      {"proxy-authorization", ""},
      {"range", ""},
      {"referer", ""},
      {"refresh", ""},
      {"retry-after", ""},
      {"server", ""},
      {"set-cookie", ""},
      {"strict-transport-security", ""},
      {"transfer-encoding", ""},
      {"user-agent", ""},
      {"vary", ""},
      {"via", ""},
      {"www-authenticate", ""},
      {"grpc-encoding", ""},
      {"grpc-message", ""},
      {"grpc-status", ""},
      {"grpc-timeout", ""},
      {"te", "trailers"},
    ]

    class Encoder
      @dynamic_table : Array({String, String})

      def initialize
        @dynamic_table = [] of {String, String}
      end

      # Encode headers into HPACK format
      def encode(headers : Hash(String, String)) : Bytes
        io = IO::Memory.new

        headers.each do |name, value|
          # Try to find in static table
          static_index = find_in_static_table(name, value)
          
          if static_index
            # Indexed header field
            encode_integer(io, static_index + 1, 7, 0x80)
          else
            # Literal header field with incremental indexing
            name_index = find_name_in_static_table(name)
            
            if name_index
              encode_integer(io, name_index + 1, 6, 0x40)
            else
              io.write_byte(0x40_u8)
              encode_string(io, name)
            end
            
            encode_string(io, value)
            @dynamic_table << {name, value}
          end
        end

        io.to_slice
      end

      private def find_in_static_table(name : String, value : String) : Int32?
        STATIC_TABLE.each_with_index do |(n, v), i|
          return i if n == name && v == value
        end
        nil
      end

      private def find_name_in_static_table(name : String) : Int32?
        STATIC_TABLE.each_with_index do |(n, _), i|
          return i if n == name
        end
        nil
      end

      private def encode_integer(io : IO::Memory, value : Int32, prefix_bits : Int32, prefix : UInt8)
        max_prefix = (1 << prefix_bits) - 1
        
        if value < max_prefix
          io.write_byte((prefix | value).to_u8)
        else
          io.write_byte((prefix | max_prefix).to_u8)
          value -= max_prefix
          
          while value >= 128
            io.write_byte(((value % 128) + 128).to_u8)
            value //= 128
          end
          
          io.write_byte(value.to_u8)
        end
      end

      private def encode_string(io : IO::Memory, str : String)
        bytes = str.to_slice
        encode_integer(io, bytes.size, 7, 0)
        io.write(bytes)
      end
    end

    class Decoder
      @dynamic_table : Array({String, String})

      def initialize
        @dynamic_table = [] of {String, String}
      end

      # Decode HPACK encoded headers
      def decode(data : Bytes) : Hash(String, String)
        headers = {} of String => String
        offset = 0

        while offset < data.size
          byte = data[offset]

          if (byte & 0x80) != 0
            # Indexed header field
            index, new_offset = decode_integer(data, offset, 7)
            offset = new_offset
            name, value = get_indexed_header(index - 1)
            headers[name] = value
          elsif (byte & 0x40) != 0
            # Literal header field with incremental indexing
            index, new_offset = decode_integer(data, offset, 6)
            offset = new_offset
            
            if index == 0
              name, offset = decode_string(data, offset)
            else
              name, _ = get_indexed_header(index - 1)
            end
            
            value, offset = decode_string(data, offset)
            headers[name] = value
            @dynamic_table << {name, value}
          else
            # Literal header field without indexing
            index, new_offset = decode_integer(data, offset, 4)
            offset = new_offset
            
            if index == 0
              name, offset = decode_string(data, offset)
            else
              name, _ = get_indexed_header(index - 1)
            end
            
            value, offset = decode_string(data, offset)
            headers[name] = value
          end
        end

        headers
      end

      private def get_indexed_header(index : Int32) : {String, String}
        if index < STATIC_TABLE.size
          STATIC_TABLE[index]
        else
          @dynamic_table[index - STATIC_TABLE.size]
        end
      end

      private def decode_integer(data : Bytes, offset : Int32, prefix_bits : Int32) : {Int32, Int32}
        max_prefix = (1 << prefix_bits) - 1
        mask = max_prefix.to_u8
        
        value = (data[offset] & mask).to_i32
        offset += 1
        
        if value < max_prefix
          return {value, offset}
        end
        
        m = 0
        loop do
          byte = data[offset]
          offset += 1
          value += ((byte & 0x7F) << m)
          m += 7
          break if (byte & 0x80) == 0
        end
        
        {value, offset}
      end

      private def decode_string(data : Bytes, offset : Int32) : {String, Int32}
        length, new_offset = decode_integer(data, offset, 7)
        str = String.new(data[new_offset, length])
        {str, new_offset + length}
      end
    end
  end
end
