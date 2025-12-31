# Protocol Buffers Descriptor Parser
# Parses FileDescriptorSet from protoc output

module Protobuf
  # Simplified descriptor types for code generation
  
  class FieldDescriptor
    property name : String
    property number : Int32
    property type : Int32
    property type_name : String?
    property label : Int32
    
    def initialize(@name, @number, @type, @type_name, @label)
    end
    
    def repeated? : Bool
      @label == 3 # LABEL_REPEATED
    end
    
    def optional? : Bool
      @label == 1 # LABEL_OPTIONAL
    end
    
    def required? : Bool
      @label == 2 # LABEL_REQUIRED
    end
    
    def crystal_type : String
      case @type
      when 1  # TYPE_DOUBLE
        "Float64"
      when 2  # TYPE_FLOAT
        "Float32"
      when 3  # TYPE_INT64
        "Int64"
      when 4  # TYPE_UINT64
        "UInt64"
      when 5  # TYPE_INT32
        "Int32"
      when 8  # TYPE_BOOL
        "Bool"
      when 9  # TYPE_STRING
        "String"
      when 11 # TYPE_MESSAGE
        @type_name.to_s.split(".").last
      when 12 # TYPE_BYTES
        "Bytes"
      when 13 # TYPE_UINT32
        "UInt32"
      when 15 # TYPE_SFIXED32
        "Int32"
      when 16 # TYPE_SFIXED64
        "Int64"
      when 17 # TYPE_SINT32
        "Int32"
      when 18 # TYPE_SINT64
        "Int64"
      else
        "Bytes"
      end
    end
  end
  
  class MessageDescriptor
    property name : String
    property fields : Array(FieldDescriptor)
    
    def initialize(@name)
      @fields = [] of FieldDescriptor
    end
  end
  
  class MethodDescriptor
    property name : String
    property input_type : String
    property output_type : String
    property client_streaming : Bool
    property server_streaming : Bool
    
    def initialize(@name, @input_type, @output_type, @client_streaming, @server_streaming)
    end
    
    def unary? : Bool
      !@client_streaming && !@server_streaming
    end
  end
  
  class ServiceDescriptor
    property name : String
    property methods : Array(MethodDescriptor)
    
    def initialize(@name)
      @methods = [] of MethodDescriptor
    end
  end
  
  class FileDescriptor
    property package : String
    property messages : Array(MessageDescriptor)
    property services : Array(ServiceDescriptor)
    
    def initialize(@package = "")
      @messages = [] of MessageDescriptor
      @services = [] of ServiceDescriptor
    end
  end
  
  # Parser for FileDescriptorSet
  class DescriptorParser
    def self.parse(data : Bytes) : Array(FileDescriptor)
      files = [] of FileDescriptor
      reader = MessageReader.new(data)
      
      while field = reader.read_field
        field_number, wire_type, field_data = field
        if field_number == 1 && wire_type == WireType::LENGTH_DELIMITED
          # This is a FileDescriptorProto
          files << parse_file_descriptor(field_data)
        end
      end
      
      files
    end
    
    private def self.parse_file_descriptor(data : Bytes) : FileDescriptor
      file = FileDescriptor.new
      reader = MessageReader.new(data)
      
      while field = reader.read_field
        field_number, wire_type, field_data = field
        case field_number
        when 2 # package
          file.package = String.new(field_data) if wire_type == WireType::LENGTH_DELIMITED
        when 4 # message_type
          if wire_type == WireType::LENGTH_DELIMITED
            file.messages << parse_message_descriptor(field_data)
          end
        when 6 # service
          if wire_type == WireType::LENGTH_DELIMITED
            file.services << parse_service_descriptor(field_data)
          end
        end
      end
      
      file
    end
    
    private def self.parse_message_descriptor(data : Bytes) : MessageDescriptor
      message = MessageDescriptor.new("")
      reader = MessageReader.new(data)
      
      while field = reader.read_field
        field_number, wire_type, field_data = field
        case field_number
        when 1 # name
          message.name = String.new(field_data) if wire_type == WireType::LENGTH_DELIMITED
        when 2 # field
          if wire_type == WireType::LENGTH_DELIMITED
            message.fields << parse_field_descriptor(field_data)
          end
        end
      end
      
      message
    end
    
    private def self.parse_field_descriptor(data : Bytes) : FieldDescriptor
      name = ""
      number = 0
      type = 0
      type_name : String? = nil
      label = 1
      
      reader = MessageReader.new(data)
      
      while field = reader.read_field
        field_number, wire_type, field_data = field
        case field_number
        when 1 # name
          name = String.new(field_data) if wire_type == WireType::LENGTH_DELIMITED
        when 3 # number
          if wire_type == WireType::VARINT
            value, _ = Protobuf.decode_varint(field_data)
            number = value.to_i32
          end
        when 4 # label
          if wire_type == WireType::VARINT
            value, _ = Protobuf.decode_varint(field_data)
            label = value.to_i32
          end
        when 5 # type
          if wire_type == WireType::VARINT
            value, _ = Protobuf.decode_varint(field_data)
            type = value.to_i32
          end
        when 6 # type_name
          type_name = String.new(field_data) if wire_type == WireType::LENGTH_DELIMITED
        end
      end
      
      FieldDescriptor.new(name, number, type, type_name, label)
    end
    
    private def self.parse_service_descriptor(data : Bytes) : ServiceDescriptor
      service = ServiceDescriptor.new("")
      reader = MessageReader.new(data)
      
      while field = reader.read_field
        field_number, wire_type, field_data = field
        case field_number
        when 1 # name
          service.name = String.new(field_data) if wire_type == WireType::LENGTH_DELIMITED
        when 2 # method
          if wire_type == WireType::LENGTH_DELIMITED
            service.methods << parse_method_descriptor(field_data)
          end
        end
      end
      
      service
    end
    
    private def self.parse_method_descriptor(data : Bytes) : MethodDescriptor
      name = ""
      input_type = ""
      output_type = ""
      client_streaming = false
      server_streaming = false
      
      reader = MessageReader.new(data)
      
      while field = reader.read_field
        field_number, wire_type, field_data = field
        case field_number
        when 1 # name
          name = String.new(field_data) if wire_type == WireType::LENGTH_DELIMITED
        when 2 # input_type
          input_type = String.new(field_data) if wire_type == WireType::LENGTH_DELIMITED
        when 3 # output_type
          output_type = String.new(field_data) if wire_type == WireType::LENGTH_DELIMITED
        when 5 # client_streaming
          if wire_type == WireType::VARINT
            value, _ = Protobuf.decode_varint(field_data)
            client_streaming = value != 0
          end
        when 6 # server_streaming
          if wire_type == WireType::VARINT
            value, _ = Protobuf.decode_varint(field_data)
            server_streaming = value != 0
          end
        end
      end
      
      MethodDescriptor.new(name, input_type, output_type, client_streaming, server_streaming)
    end
  end
end
