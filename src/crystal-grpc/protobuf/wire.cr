# Protocol Buffers Wire Format Implementation
# Implements varint encoding and basic wire types

module Protobuf
  # Wire types for Protocol Buffers
  enum WireType : UInt8
    VARINT           = 0
    FIXED64          = 1
    LENGTH_DELIMITED = 2
    START_GROUP      = 3 # Deprecated
    END_GROUP        = 4 # Deprecated
    FIXED32          = 5
  end

  # Encode a varint (variable-length integer)
  def self.encode_varint(value : UInt64) : Bytes
    return Bytes[0] if value == 0

    result = [] of UInt8
    while value != 0
      byte = (value & 0x7F).to_u8
      value >>= 7
      byte |= 0x80 if value != 0
      result << byte
    end
    Bytes.new(result.to_unsafe, result.size)
  end

  # Decode a varint from a Slice
  def self.decode_varint(data : Bytes, offset : Int32 = 0) : {UInt64, Int32}
    result = 0_u64
    shift = 0
    pos = offset

    loop do
      raise "Varint overflow" if pos >= data.size
      byte = data[pos]
      pos += 1

      result |= ((byte & 0x7F).to_u64 << shift)
      break if (byte & 0x80) == 0

      shift += 7
      raise "Varint too long" if shift >= 64
    end

    {result, pos}
  end

  # Encode a signed varint using ZigZag encoding
  def self.encode_sint(value : Int64) : Bytes
    unsigned = ((value << 1) ^ (value >> 63)).to_u64
    encode_varint(unsigned)
  end

  # Decode a signed varint using ZigZag decoding
  def self.decode_sint(data : Bytes, offset : Int32 = 0) : {Int64, Int32}
    unsigned, new_offset = decode_varint(data, offset)
    signed = (unsigned >> 1).to_i64 ^ -(unsigned & 1).to_i64
    {signed, new_offset}
  end

  # Encode a field key (field number + wire type)
  def self.encode_key(field_number : UInt32, wire_type : WireType) : Bytes
    key = (field_number << 3) | wire_type.value
    encode_varint(key.to_u64)
  end

  # Decode a field key
  def self.decode_key(data : Bytes, offset : Int32 = 0) : {UInt32, WireType, Int32}
    key, new_offset = decode_varint(data, offset)
    field_number = (key >> 3).to_u32
    wire_type = WireType.new((key & 0x7).to_u8)
    {field_number, wire_type, new_offset}
  end

  # Encode a length-delimited field (strings, bytes, embedded messages)
  def self.encode_length_delimited(field_number : UInt32, data : Bytes) : Bytes
    io = IO::Memory.new
    io.write(encode_key(field_number, WireType::LENGTH_DELIMITED))
    io.write(encode_varint(data.size.to_u64))
    io.write(data)
    io.to_slice
  end

  # Encode a string field
  def self.encode_string(field_number : UInt32, value : String) : Bytes
    encode_length_delimited(field_number, value.to_slice)
  end

  # Encode a varint field
  def self.encode_varint_field(field_number : UInt32, value : UInt64) : Bytes
    io = IO::Memory.new
    io.write(encode_key(field_number, WireType::VARINT))
    io.write(encode_varint(value))
    io.to_slice
  end

  # Encode a fixed32 field
  def self.encode_fixed32(field_number : UInt32, value : UInt32) : Bytes
    io = IO::Memory.new
    io.write(encode_key(field_number, WireType::FIXED32))
    io.write_bytes(value, IO::ByteFormat::LittleEndian)
    io.to_slice
  end

  # Encode a fixed64 field
  def self.encode_fixed64(field_number : UInt32, value : UInt64) : Bytes
    io = IO::Memory.new
    io.write(encode_key(field_number, WireType::FIXED64))
    io.write_bytes(value, IO::ByteFormat::LittleEndian)
    io.to_slice
  end

  # Message builder for constructing protobuf messages
  class MessageBuilder
    @io : IO::Memory

    def initialize
      @io = IO::Memory.new
    end

    def add_varint(field_number : UInt32, value : UInt64)
      @io.write(Protobuf.encode_varint_field(field_number, value))
      self
    end

    def add_string(field_number : UInt32, value : String)
      @io.write(Protobuf.encode_string(field_number, value))
      self
    end

    def add_bytes(field_number : UInt32, value : Bytes)
      @io.write(Protobuf.encode_length_delimited(field_number, value))
      self
    end

    def add_fixed32(field_number : UInt32, value : UInt32)
      @io.write(Protobuf.encode_fixed32(field_number, value))
      self
    end

    def add_fixed64(field_number : UInt32, value : UInt64)
      @io.write(Protobuf.encode_fixed64(field_number, value))
      self
    end

    def to_bytes : Bytes
      @io.to_slice
    end
  end

  # Message reader for parsing protobuf messages
  class MessageReader
    @data : Bytes
    @offset : Int32

    def initialize(@data : Bytes)
      @offset = 0
    end

    def has_more? : Bool
      @offset < @data.size
    end

    def read_field : {UInt32, WireType, Bytes} | Nil
      return nil unless has_more?

      field_number, wire_type, new_offset = Protobuf.decode_key(@data, @offset)
      @offset = new_offset

      case wire_type
      when WireType::VARINT
        value, new_offset = Protobuf.decode_varint(@data, @offset)
        @offset = new_offset
        value_bytes = Protobuf.encode_varint(value)
        {field_number, wire_type, value_bytes}
      when WireType::LENGTH_DELIMITED
        length, new_offset = Protobuf.decode_varint(@data, @offset)
        @offset = new_offset
        value = @data[@offset, length.to_i32]
        @offset += length.to_i32
        {field_number, wire_type, value}
      when WireType::FIXED32
        value = @data[@offset, 4]
        @offset += 4
        {field_number, wire_type, value}
      when WireType::FIXED64
        value = @data[@offset, 8]
        @offset += 8
        {field_number, wire_type, value}
      else
        raise "Unsupported wire type: #{wire_type}"
      end
    end

    def read_string(field_number : UInt32) : String?
      loop do
        field = read_field
        return nil if field.nil?

        fn, wire_type, data = field
        if fn == field_number && wire_type == WireType::LENGTH_DELIMITED
          return String.new(data)
        end
      end
    end

    def read_varint(field_number : UInt32) : UInt64?
      loop do
        field = read_field
        return nil if field.nil?

        fn, wire_type, data = field
        if fn == field_number && wire_type == WireType::VARINT
          value, _ = Protobuf.decode_varint(data)
          return value
        end
      end
    end
  end
end
