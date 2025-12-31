# Data Flow Diagrams

## Unary RPC Call Flow

```
┌──────────┐                                                    ┌──────────┐
│  Client  │                                                    │  Server  │
└────┬─────┘                                                    └────┬─────┘
     │                                                               │
     │ 1. TCP Connect                                               │
     ├──────────────────────────────────────────────────────────────>│
     │                                                               │
     │ 2. HTTP/2 Preface: "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"        │
     ├──────────────────────────────────────────────────────────────>│
     │                                                               │
     │ 3. SETTINGS Frame                                             │
     ├──────────────────────────────────────────────────────────────>│
     │                                                               │
     │ 4. SETTINGS Frame                                             │
     │<──────────────────────────────────────────────────────────────┤
     │                                                               │
     │ 5. SETTINGS ACK                                               │
     ├──────────────────────────────────────────────────────────────>│
     │                                                               │
     │ 6. SETTINGS ACK                                               │
     │<──────────────────────────────────────────────────────────────┤
     │                                                               │
     │ 7. HEADERS Frame (stream 1)                                   │
     │    :method = POST                                             │
     │    :scheme = http                                             │
     │    :path = /service.Service/Method                            │
     │    :authority = host:port                                     │
     │    content-type = application/grpc                            │
     ├──────────────────────────────────────────────────────────────>│
     │                                                               │
     │ 8. DATA Frame (stream 1, END_STREAM)                          │
     │    [Compressed-Flag(1) + Length(4) + Protobuf Message]        │
     ├──────────────────────────────────────────────────────────────>│
     │                                                               │
     │                                                               ├─┐
     │                                                               │ │ Process
     │                                                               │ │ Request
     │                                                               │<┘
     │                                                               │
     │ 9. HEADERS Frame (stream 1)                                   │
     │    :status = 200                                              │
     │    content-type = application/grpc                            │
     │<──────────────────────────────────────────────────────────────┤
     │                                                               │
     │ 10. DATA Frame (stream 1)                                     │
     │     [Compressed-Flag(1) + Length(4) + Protobuf Response]      │
     │<──────────────────────────────────────────────────────────────┤
     │                                                               │
     │ 11. HEADERS Frame (stream 1, END_STREAM)                      │
     │     grpc-status = 0                                           │
     │     grpc-message = OK                                         │
     │<──────────────────────────────────────────────────────────────┤
     │                                                               │
     ▼                                                               ▼
```

## Protocol Buffers Message Encoding

```
Input: { field1: 150, field2: "testing" }

┌─────────────────────────────────────────────────────────────┐
│ 1. Encode field 1 (varint)                                  │
│    Key: (field_number=1 << 3) | wire_type=0 = 0x08         │
│    Value: 150 (varint) = 0x96 0x01                          │
│    Result: [0x08, 0x96, 0x01]                               │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. Encode field 2 (string/length-delimited)                 │
│    Key: (field_number=2 << 3) | wire_type=2 = 0x12         │
│    Length: 7 (varint) = 0x07                                │
│    Value: "testing" = [0x74, 0x65, 0x73, 0x74, 0x69, ...]  │
│    Result: [0x12, 0x07, 0x74, 0x65, 0x73, 0x74, ...]       │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. Concatenate                                              │
│    [0x08, 0x96, 0x01, 0x12, 0x07, 0x74, 0x65, 0x73, ...]   │
└─────────────────────────────────────────────────────────────┘
```

## HTTP/2 Frame Structure

```
┌──────────────────────────────────────────────────────────────┐
│                        Frame Header (9 bytes)                 │
├──────────────────────────────────────────────────────────────┤
│  Length (24 bits)   │  Type (8)  │  Flags (8)  │            │
├─────────────────────┼────────────┼─────────────┤            │
│  0x00  │  0x00  │  0x0A  │  0x00  │  0x01  │              │
│        Length = 10         │  DATA  │END_STREAM│              │
├────────────────────────────┴────────┴──────────┴────────────┤
│              Stream Identifier (31 bits) + R (1 bit)         │
├──────────────────────────────────────────────────────────────┤
│  0x00  │  0x00  │  0x00  │  0x01  │                         │
│        Stream ID = 1               │                         │
├──────────────────────────────────────────────────────────────┤
│                        Frame Payload (10 bytes)               │
├──────────────────────────────────────────────────────────────┤
│  Payload data ...                                             │
└──────────────────────────────────────────────────────────────┘
```

## gRPC Message Frame

```
┌──────────────────────────────────────────────────────────────┐
│                      gRPC Message Frame                       │
├──────────────────────────────────────────────────────────────┤
│  Compressed Flag (1 byte)                                     │
├──────────────────────────────────────────────────────────────┤
│  0x00  │  (0 = not compressed, 1 = compressed)              │
├──────────────────────────────────────────────────────────────┤
│  Message Length (4 bytes, big-endian)                         │
├──────────────────────────────────────────────────────────────┤
│  0x00  │  0x00  │  0x00  │  0x0A  │  (length = 10)          │
├──────────────────────────────────────────────────────────────┤
│  Protobuf Message (10 bytes)                                  │
├──────────────────────────────────────────────────────────────┤
│  [0x08, 0x96, 0x01, 0x12, 0x07, 0x74, 0x65, 0x73, ...]      │
└──────────────────────────────────────────────────────────────┘
```

## HPACK Header Compression

```
Input Headers:
  :method = POST
  :path = /service/Method
  content-type = application/grpc

┌─────────────────────────────────────────────────────────────┐
│ 1. Lookup in Static Table                                   │
│    Entry 2: :method = POST                                  │
│    Encode as: Indexed Header (0x82)                         │
│    Result: [0x82]                                            │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. :path not in static table with this value                │
│    Encode as: Literal with Incremental Indexing             │
│    Name index: 4 (:path in static table)                    │
│    Value: encode string "/service/Method"                   │
│    Result: [0x44, 0x10, 0x2f, 0x73, 0x65, ...]             │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. content-type not in static table with this value         │
│    Encode as: Literal with Incremental Indexing             │
│    Name index: 31 (content-type in static table)            │
│    Value: encode string "application/grpc"                  │
│    Result: [0x5F, 0x11, 0x61, 0x70, 0x70, ...]             │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. Concatenate all encoded headers                          │
│    [0x82, 0x44, 0x10, 0x2f, ..., 0x5F, 0x11, ...]          │
└─────────────────────────────────────────────────────────────┘
```

## Server Request Processing

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Receive HEADERS Frame                                     │
│    - Decode with HPACK                                       │
│    - Extract :path = /service/Method                         │
│    - Store in stream.headers                                 │
└────────────────────────────┬────────────────────────────────┘
                             ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. Receive DATA Frame                                        │
│    - Accumulate in stream.data                               │
│    - Check END_STREAM flag                                   │
└────────────────────────────┬────────────────────────────────┘
                             ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. Parse gRPC Message Frame                                  │
│    - Read compressed flag (1 byte)                           │
│    - Read message length (4 bytes)                           │
│    - Extract protobuf message                                │
└────────────────────────────┬────────────────────────────────┘
                             ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. Find Handler                                              │
│    - Lookup in ServiceRegistry                               │
│    - Match /service/Method                                   │
└────────────────────────────┬────────────────────────────────┘
                             ↓
┌─────────────────────────────────────────────────────────────┐
│ 5. Call Handler                                              │
│    - Pass protobuf message bytes                             │
│    - Handler decodes, processes, encodes response            │
│    - Returns response protobuf bytes                         │
└────────────────────────────┬────────────────────────────────┘
                             ↓
┌─────────────────────────────────────────────────────────────┐
│ 6. Build gRPC Response                                       │
│    - Encode response as gRPC message frame                   │
│    - Build response headers                                  │
└────────────────────────────┬────────────────────────────────┘
                             ↓
┌─────────────────────────────────────────────────────────────┐
│ 7. Send Response                                             │
│    - HEADERS frame (:status = 200)                           │
│    - DATA frame (gRPC message)                               │
│    - HEADERS frame (trailers with grpc-status)               │
└─────────────────────────────────────────────────────────────┘
```

## Fiber Concurrency Model

```
┌─────────────────────────────────────────────────────────────┐
│                      Main Fiber                              │
│  - Server.start                                              │
│  - Accept connections                                        │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   ├─ spawn ───────────────────────────────┐
                   │                                        │
                   │                                        ▼
                   │              ┌──────────────────────────────────┐
                   │              │  Connection Fiber 1              │
                   │              │  - Read frames                   │
                   │              │  - Process requests              │
                   │              │  - Send responses                │
                   │              └──────────────────────────────────┘
                   │
                   ├─ spawn ───────────────────────────────┐
                   │                                        │
                   │                                        ▼
                   │              ┌──────────────────────────────────┐
                   │              │  Connection Fiber 2              │
                   │              │  - Read frames                   │
                   │              │  - Process requests              │
                   │              │  - Send responses                │
                   │              └──────────────────────────────────┘
                   │
                   ├─ spawn ───────────────────────────────┐
                   │                                        │
                   ▼                                        ▼
                  ...             ┌──────────────────────────────────┐
                                  │  Connection Fiber N              │
                                  │  - Read frames                   │
                                  │  - Process requests              │
                                  │  - Send responses                │
                                  └──────────────────────────────────┘

Each fiber is lightweight (few KB of stack)
Crystal's scheduler handles fiber coordination
Non-blocking I/O keeps fibers from blocking each other
```

## Stream Multiplexing

```
Single TCP Connection
═══════════════════════════════════════════════════════════════

Stream 1 (Request A)
───────────────────────────────────────────────────────────────
HEADERS → DATA → [PROCESSING] → HEADERS → DATA → TRAILERS
───────────────────────────────────────────────────────────────

Stream 3 (Request B)  
───────────────────────────────────────────────────────────────
   HEADERS → DATA → [PROCESSING] → HEADERS → DATA → TRAILERS
───────────────────────────────────────────────────────────────

Stream 5 (Request C)
───────────────────────────────────────────────────────────────
      HEADERS → DATA → [PROCESSING] → HEADERS → DATA → TRAILERS
───────────────────────────────────────────────────────────────

Stream 0 (Connection)
───────────────────────────────────────────────────────────────
SETTINGS ←→ PING ←→ WINDOW_UPDATE ←→ GOAWAY
───────────────────────────────────────────────────────────────

Frames from all streams are interleaved on the same connection
Stream IDs identify which request each frame belongs to
Client uses odd IDs (1, 3, 5, ...), Server uses even IDs (2, 4, 6, ...)
```
