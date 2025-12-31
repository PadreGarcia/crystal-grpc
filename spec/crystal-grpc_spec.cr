require "./spec_helper"

describe Protobuf do
  describe ".encode_varint" do
    it "encodes 0" do
      result = Protobuf.encode_varint(0_u64)
      result.should eq(Bytes[0])
    end

    it "encodes 1" do
      result = Protobuf.encode_varint(1_u64)
      result.should eq(Bytes[1])
    end

    it "encodes 127" do
      result = Protobuf.encode_varint(127_u64)
      result.should eq(Bytes[127])
    end

    it "encodes 128" do
      result = Protobuf.encode_varint(128_u64)
      result.should eq(Bytes[0x80, 0x01])
    end

    it "encodes 300" do
      result = Protobuf.encode_varint(300_u64)
      result.should eq(Bytes[0xAC, 0x02])
    end
  end

  describe ".decode_varint" do
    it "decodes 0" do
      value, offset = Protobuf.decode_varint(Bytes[0])
      value.should eq(0_u64)
      offset.should eq(1)
    end

    it "decodes 1" do
      value, offset = Protobuf.decode_varint(Bytes[1])
      value.should eq(1_u64)
      offset.should eq(1)
    end

    it "decodes 127" do
      value, offset = Protobuf.decode_varint(Bytes[127])
      value.should eq(127_u64)
      offset.should eq(1)
    end

    it "decodes 128" do
      value, offset = Protobuf.decode_varint(Bytes[0x80, 0x01])
      value.should eq(128_u64)
      offset.should eq(2)
    end

    it "decodes 300" do
      value, offset = Protobuf.decode_varint(Bytes[0xAC, 0x02])
      value.should eq(300_u64)
      offset.should eq(2)
    end
  end

  describe ".encode_sint" do
    it "encodes 0" do
      result = Protobuf.encode_sint(0_i64)
      result.should eq(Bytes[0])
    end

    it "encodes -1" do
      result = Protobuf.encode_sint(-1_i64)
      result.should eq(Bytes[1])
    end

    it "encodes 1" do
      result = Protobuf.encode_sint(1_i64)
      result.should eq(Bytes[2])
    end

    it "encodes -2" do
      result = Protobuf.encode_sint(-2_i64)
      result.should eq(Bytes[3])
    end
  end

  describe "MessageBuilder" do
    it "builds a message with string field" do
      builder = Protobuf::MessageBuilder.new
      builder.add_string(1_u32, "test")
      result = builder.to_bytes
      result.size.should be > 0
    end

    it "builds a message with varint field" do
      builder = Protobuf::MessageBuilder.new
      builder.add_varint(1_u32, 42_u64)
      result = builder.to_bytes
      result.size.should be > 0
    end

    it "builds a message with multiple fields" do
      builder = Protobuf::MessageBuilder.new
      builder.add_varint(1_u32, 42_u64)
      builder.add_string(2_u32, "hello")
      result = builder.to_bytes
      result.size.should be > 0
    end
  end
end

describe HTTP2::Frame do
  describe ".parse" do
    it "parses a SETTINGS frame" do
      # Empty SETTINGS frame
      data = Bytes[
        0x00, 0x00, 0x00, # Length: 0
        0x04,             # Type: SETTINGS
        0x00,             # Flags: none
        0x00, 0x00, 0x00, 0x00, # Stream ID: 0
      ]
      frame = HTTP2::Frame.parse(data)
      frame.type.should eq(HTTP2::FrameType::SETTINGS)
      frame.stream_id.should eq(0)
      frame.length.should eq(0)
    end
  end

  describe "#to_bytes" do
    it "serializes a DATA frame" do
      data = Bytes[1, 2, 3, 4, 5]
      frame = HTTP2::DataFrame.new(1_u32, data, end_stream: false)
      bytes = frame.to_bytes
      bytes.size.should eq(9 + 5) # header + payload
    end
  end
end

describe GRPC do
  describe ".encode_message" do
    it "encodes a message" do
      message = Bytes[1, 2, 3, 4, 5]
      result = GRPC.encode_message(message, compressed: false)
      result.size.should eq(5 + 5) # 1 byte flag + 4 bytes length + message
      result[0].should eq(0) # Not compressed
    end
  end

  describe ".decode_message" do
    it "decodes a message" do
      message = Bytes[1, 2, 3, 4, 5]
      encoded = GRPC.encode_message(message, compressed: false)
      compressed, decoded = GRPC.decode_message(encoded)
      compressed.should be_false
      decoded.should eq(message)
    end
  end

  describe "Status" do
    it "creates OK status" do
      status = GRPC::Status.ok
      status.ok?.should be_true
      status.code.should eq(GRPC::StatusCode::OK)
    end

    it "creates error status" do
      status = GRPC::Status.invalid_argument("Bad request")
      status.ok?.should be_false
      status.code.should eq(GRPC::StatusCode::INVALID_ARGUMENT)
      status.message.should eq("Bad request")
    end
  end
end
