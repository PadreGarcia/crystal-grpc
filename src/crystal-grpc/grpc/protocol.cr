# gRPC Wire Protocol Implementation
# Implements gRPC framing over HTTP/2

module GRPC
  # gRPC status codes
  enum StatusCode : UInt32
    OK                  =  0
    CANCELLED           =  1
    UNKNOWN             =  2
    INVALID_ARGUMENT    =  3
    DEADLINE_EXCEEDED   =  4
    NOT_FOUND           =  5
    ALREADY_EXISTS      =  6
    PERMISSION_DENIED   =  7
    RESOURCE_EXHAUSTED  =  8
    FAILED_PRECONDITION =  9
    ABORTED             = 10
    OUT_OF_RANGE        = 11
    UNIMPLEMENTED       = 12
    INTERNAL            = 13
    UNAVAILABLE         = 14
    DATA_LOSS           = 15
    UNAUTHENTICATED     = 16
  end

  # gRPC message frame format:
  # - Compressed-Flag (1 byte): 0 = not compressed, 1 = compressed
  # - Message-Length (4 bytes): Length of the message in big-endian
  # - Message (variable): The actual protobuf message
  
  # Encode a gRPC message
  def self.encode_message(message : Bytes, compressed : Bool = false) : Bytes
    io = IO::Memory.new
    
    # Compressed flag
    io.write_byte(compressed ? 1_u8 : 0_u8)
    
    # Message length (4 bytes, big-endian)
    length = message.size.to_u32
    io.write_byte((length >> 24).to_u8)
    io.write_byte((length >> 16).to_u8)
    io.write_byte((length >> 8).to_u8)
    io.write_byte(length.to_u8)
    
    # Message data
    io.write(message)
    
    io.to_slice
  end

  # Decode a gRPC message
  def self.decode_message(data : Bytes) : {Bool, Bytes}
    raise "Message too short" if data.size < 5
    
    compressed = data[0] != 0
    length = (data[1].to_u32 << 24) | (data[2].to_u32 << 16) | 
             (data[3].to_u32 << 8) | data[4].to_u32
    
    raise "Invalid message length" if data.size < 5 + length
    
    message = data[5, length]
    {compressed, message}
  end

  # gRPC method descriptor
  class MethodDescriptor
    property service_name : String
    property method_name : String
    property full_name : String

    def initialize(@service_name : String, @method_name : String)
      @full_name = "/#{@service_name}/#{@method_name}"
    end
  end

  # gRPC call context
  class CallContext
    property metadata : Hash(String, String)
    property timeout : Time::Span?

    def initialize
      @metadata = {} of String => String
      @timeout = nil
    end

    def add_metadata(key : String, value : String)
      @metadata[key] = value
    end

    def set_timeout(timeout : Time::Span)
      @timeout = timeout
    end
  end

  # gRPC status
  class Status
    property code : StatusCode
    property message : String
    property details : Bytes

    def initialize(@code : StatusCode, @message : String = "", @details : Bytes = Bytes.empty)
    end

    def ok? : Bool
      @code == StatusCode::OK
    end

    def self.ok : Status
      Status.new(StatusCode::OK, "OK")
    end

    def self.cancelled(message : String = "Cancelled") : Status
      Status.new(StatusCode::CANCELLED, message)
    end

    def self.unknown(message : String = "Unknown error") : Status
      Status.new(StatusCode::UNKNOWN, message)
    end

    def self.invalid_argument(message : String = "Invalid argument") : Status
      Status.new(StatusCode::INVALID_ARGUMENT, message)
    end

    def self.not_found(message : String = "Not found") : Status
      Status.new(StatusCode::NOT_FOUND, message)
    end

    def self.internal(message : String = "Internal error") : Status
      Status.new(StatusCode::INTERNAL, message)
    end

    def self.unimplemented(message : String = "Unimplemented") : Status
      Status.new(StatusCode::UNIMPLEMENTED, message)
    end
  end

  # gRPC request
  class Request
    property method : MethodDescriptor
    property context : CallContext
    property message : Bytes

    def initialize(@method : MethodDescriptor, @message : Bytes)
      @context = CallContext.new
    end
  end

  # gRPC response
  class Response
    property status : Status
    property message : Bytes
    property metadata : Hash(String, String)

    def initialize(@message : Bytes, @status : Status = Status.ok)
      @metadata = {} of String => String
    end

    def ok? : Bool
      @status.ok?
    end
  end

  # Service handler interface
  abstract class ServiceHandler
    abstract def handle(request : Request) : Response
  end

  # Method handler (simple unary RPC)
  alias UnaryHandler = Proc(Bytes, Bytes)

  # Service registry
  class ServiceRegistry
    @services : Hash(String, Hash(String, UnaryHandler))

    def initialize
      @services = {} of String => Hash(String, UnaryHandler)
    end

    def register_service(service_name : String)
      @services[service_name] = {} of String => UnaryHandler
    end

    def register_method(service_name : String, method_name : String, handler : UnaryHandler)
      @services[service_name] ||= {} of String => UnaryHandler
      @services[service_name][method_name] = handler
    end

    def find_handler(full_method : String) : UnaryHandler?
      # Parse /ServiceName/MethodName
      parts = full_method.split("/")
      return nil if parts.size != 3 || parts[0] != ""
      
      service_name = parts[1]
      method_name = parts[2]
      
      service = @services[service_name]?
      return nil unless service
      
      service[method_name]?
    end

    def has_service?(service_name : String) : Bool
      @services.has_key?(service_name)
    end

    def has_method?(service_name : String, method_name : String) : Bool
      service = @services[service_name]?
      return false unless service
      service.has_key?(method_name)
    end
  end
end
