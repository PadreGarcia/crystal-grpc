# Crystal gRPC Code Generator
# Generates strongly-typed Crystal client and server stubs from FileDescriptorSet

require "./descriptor"

module Protobuf
  class CodeGenerator
    property package : String
    
    def initialize(@package = "")
    end
    
    def generate(files : Array(FileDescriptor)) : String
      output = IO::Memory.new
      
      files.each do |file|
        @package = file.package unless file.package.empty?
        
        # Generate messages
        file.messages.each do |message|
          generate_message(output, message)
        end
        
        # Generate services
        file.services.each do |service|
          generate_service(output, service)
        end
      end
      
      output.to_s
    end
    
    private def generate_message(io : IO, message : MessageDescriptor)
      io << "# Generated message type\n"
      io << "class #{message.name}\n"
      
      # Properties
      message.fields.each do |field|
        if field.repeated?
          io << "  property #{field.name} : Array(#{field.crystal_type})\n"
        elsif field.optional?
          io << "  property #{field.name} : #{field.crystal_type}?\n"
        else
          io << "  property #{field.name} : #{field.crystal_type}\n"
        end
      end
      
      io << "\n"
      
      # Constructor
      io << "  def initialize(\n"
      message.fields.each_with_index do |field, idx|
        comma = idx < message.fields.size - 1 ? "," : ""
        if field.repeated?
          io << "    @#{field.name} : Array(#{field.crystal_type}) = [] of #{field.crystal_type}#{comma}\n"
        elsif field.optional?
          io << "    @#{field.name} : #{field.crystal_type}? = nil#{comma}\n"
        else
          io << "    @#{field.name} : #{field.crystal_type}#{comma}\n"
        end
      end
      io << "  )\n"
      io << "  end\n\n"
      
      # Encode method
      io << "  def encode : Bytes\n"
      io << "    builder = Protobuf::MessageBuilder.new\n"
      message.fields.each do |field|
        field_num = "#{field.number}_u32"
        case field.type
        when 9 # STRING
          if field.repeated?
            io << "    @#{field.name}.each { |v| builder.add_string(#{field_num}, v) }\n"
          elsif field.optional?
            io << "    builder.add_string(#{field_num}, @#{field.name}) if @#{field.name}\n"
          else
            io << "    builder.add_string(#{field_num}, @#{field.name})\n"
          end
        when 3, 4, 5, 13 # INT64, UINT64, INT32, UINT32
          if field.repeated?
            io << "    @#{field.name}.each { |v| builder.add_varint(#{field_num}, v.to_u64) }\n"
          elsif field.optional?
            io << "    builder.add_varint(#{field_num}, @#{field.name}.to_u64) if @#{field.name}\n"
          else
            io << "    builder.add_varint(#{field_num}, @#{field.name}.to_u64)\n"
          end
        when 8 # BOOL
          if field.repeated?
            io << "    @#{field.name}.each { |v| builder.add_varint(#{field_num}, v ? 1_u64 : 0_u64) }\n"
          elsif field.optional?
            io << "    builder.add_varint(#{field_num}, @#{field.name} ? 1_u64 : 0_u64) if @#{field.name}\n"
          else
            io << "    builder.add_varint(#{field_num}, @#{field.name} ? 1_u64 : 0_u64)\n"
          end
        when 12 # BYTES
          if field.repeated?
            io << "    @#{field.name}.each { |v| builder.add_bytes(#{field_num}, v) }\n"
          elsif field.optional?
            io << "    builder.add_bytes(#{field_num}, @#{field.name}) if @#{field.name}\n"
          else
            io << "    builder.add_bytes(#{field_num}, @#{field.name})\n"
          end
        end
      end
      io << "    builder.to_bytes\n"
      io << "  end\n\n"
      
      # Decode method
      io << "  def self.decode(data : Bytes) : #{message.name}\n"
      io << "    instance = allocate\n"
      message.fields.each do |field|
        if field.repeated?
          io << "    #{field.name}_array = [] of #{field.crystal_type}\n"
        end
      end
      io << "    reader = Protobuf::MessageReader.new(data)\n"
      io << "    while field = reader.read_field\n"
      io << "      field_number, wire_type, field_data = field\n"
      io << "      case field_number\n"
      message.fields.each do |field|
        io << "      when #{field.number}\n"
        case field.type
        when 9 # STRING
          if field.repeated?
            io << "        #{field.name}_array << String.new(field_data)\n"
          else
            io << "        instance.@#{field.name} = String.new(field_data)\n"
          end
        when 3, 4, 5, 13 # INT types
          if field.repeated?
            io << "        value, _ = Protobuf.decode_varint(field_data)\n"
            io << "        #{field.name}_array << value.to_#{field.crystal_type.downcase}\n"
          else
            io << "        value, _ = Protobuf.decode_varint(field_data)\n"
            io << "        instance.@#{field.name} = value.to_#{field.crystal_type.downcase}\n"
          end
        when 8 # BOOL
          if field.repeated?
            io << "        value, _ = Protobuf.decode_varint(field_data)\n"
            io << "        #{field.name}_array << (value != 0)\n"
          else
            io << "        value, _ = Protobuf.decode_varint(field_data)\n"
            io << "        instance.@#{field.name} = (value != 0)\n"
          end
        when 12 # BYTES
          if field.repeated?
            io << "        #{field.name}_array << field_data\n"
          else
            io << "        instance.@#{field.name} = field_data\n"
          end
        end
      end
      io << "      end\n"
      io << "    end\n"
      message.fields.each do |field|
        if field.repeated?
          io << "    instance.@#{field.name} = #{field.name}_array\n"
        end
      end
      io << "    instance\n"
      io << "  end\n"
      io << "end\n\n"
    end
    
    private def generate_service(io : IO, service : ServiceDescriptor)
      # Generate client stub
      generate_client_stub(io, service)
      
      # Generate server stub
      generate_server_stub(io, service)
    end
    
    private def generate_client_stub(io : IO, service : ServiceDescriptor)
      io << "# Generated client stub for #{service.name}\n"
      io << "class #{service.name}Client\n"
      io << "  property channel : GRPC::ClientChannel\n\n"
      
      io << "  def initialize(host : String, port : Int32)\n"
      io << "    @channel = GRPC::ClientChannel.new(host, port)\n"
      io << "    @channel.connect\n"
      io << "  end\n\n"
      
      service.methods.each do |method|
        next unless method.unary? # Only support unary for now
        
        input_type = method.input_type.split(".").last
        output_type = method.output_type.split(".").last
        
        io << "  def #{method.name.underscore}(request : #{input_type}, timeout : Time::Span? = nil) : #{output_type}\n"
        io << "    request_bytes = request.encode\n"
        io << "    response = @channel.call(\n"
        io << "      \"#{@package}.#{service.name}\",\n"
        io << "      \"#{method.name}\",\n"
        io << "      request_bytes,\n"
        io << "      timeout\n"
        io << "    )\n"
        io << "    raise \"RPC failed: \#{response.status.message}\" unless response.ok?\n"
        io << "    #{output_type}.decode(response.message)\n"
        io << "  end\n\n"
      end
      
      io << "  def close\n"
      io << "    @channel.close\n"
      io << "  end\n"
      io << "end\n\n"
    end
    
    private def generate_server_stub(io : IO, service : ServiceDescriptor)
      io << "# Generated server stub for #{service.name}\n"
      io << "abstract class #{service.name}Service\n"
      
      service.methods.each do |method|
        next unless method.unary? # Only support unary for now
        
        input_type = method.input_type.split(".").last
        output_type = method.output_type.split(".").last
        
        io << "  abstract def #{method.name.underscore}(request : #{input_type}) : #{output_type}\n"
      end
      
      io << "end\n\n"
      
      # Generate registration helper
      io << "# Helper to register #{service.name} with gRPC server\n"
      io << "def register_#{service.name.underscore}_service(server : GRPC::Server, service : #{service.name}Service)\n"
      io << "  server.register_service(\"#{@package}.#{service.name}\")\n"
      
      service.methods.each do |method|
        next unless method.unary?
        
        input_type = method.input_type.split(".").last
        output_type = method.output_type.split(".").last
        
        io << "  server.register_method(\"#{@package}.#{service.name}\", \"#{method.name}\") do |request_bytes|\n"
        io << "    request = #{input_type}.decode(request_bytes)\n"
        io << "    response = service.#{method.name.underscore}(request)\n"
        io << "    response.encode\n"
        io << "  end\n"
      end
      
      io << "end\n\n"
    end
  end
end

# String extension for underscore conversion
class String
  def underscore : String
    self.gsub(/([A-Z]+)([A-Z][a-z])/, "\\1_\\2")
        .gsub(/([a-z\d])([A-Z])/, "\\1_\\2")
        .downcase
  end
end
