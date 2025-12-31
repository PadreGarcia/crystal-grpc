# Contributing to Crystal gRPC

Thank you for your interest in contributing to Crystal gRPC! This document provides guidelines for contributing to this project.

## Code of Conduct

Be respectful and constructive in all interactions with the community.

## Development Setup

1. **Install Crystal**
   - Crystal 1.18.2 or higher is required
   - Visit [crystal-lang.org](https://crystal-lang.org/install/) for installation instructions

2. **Clone the repository**
   ```bash
   git clone https://github.com/PadreGarcia/crystal-grpc.git
   cd crystal-grpc
   ```

3. **Install dependencies**
   ```bash
   shards install
   ```

4. **Run tests**
   ```bash
   crystal spec
   ```

## Project Structure

```
crystal-grpc/
├── src/
│   ├── crystal-grpc.cr              # Main entry point
│   └── crystal-grpc/
│       ├── protobuf/                # Protocol Buffers implementation
│       │   └── wire.cr
│       ├── http2/                   # HTTP/2 implementation
│       │   ├── frame.cr
│       │   ├── hpack.cr
│       │   ├── stream.cr
│       │   └── connection.cr
│       └── grpc/                    # gRPC implementation
│           ├── protocol.cr
│           ├── server.cr
│           └── client.cr
├── spec/                            # Tests
├── examples/                        # Example applications
└── docs/                            # Documentation
```

## Making Changes

### 1. Create a Branch
```bash
git checkout -b feature/my-feature
# or
git checkout -b fix/my-bugfix
```

### 2. Write Code

- Follow Crystal coding conventions
- Keep functions small and focused
- Use meaningful variable names
- Add comments for complex logic

**Code Style Guidelines:**
- Use 2 spaces for indentation
- Use snake_case for methods and variables
- Use PascalCase for classes and modules
- Keep lines under 120 characters when possible

### 3. Write Tests

All new features should include tests:

```crystal
describe MyFeature do
  it "does something" do
    result = MyFeature.do_something
    result.should eq(expected_value)
  end
end
```

### 4. Run Tests

```bash
# Run all tests
crystal spec

# Run specific test file
crystal spec spec/my_feature_spec.cr
```

### 5. Format Code

```bash
crystal tool format src/ spec/ examples/
```

### 6. Commit Changes

Write clear, concise commit messages:

```bash
git commit -m "Add feature: description of what was added"
# or
git commit -m "Fix: description of what was fixed"
```

### 7. Push and Create Pull Request

```bash
git push origin feature/my-feature
```

Then create a pull request on GitHub.

## Areas for Contribution

### High Priority
- [ ] Streaming RPC support (server streaming, client streaming, bidirectional)
- [ ] Compression support (gzip)
- [ ] TLS/SSL support
- [ ] More comprehensive tests
- [ ] Performance benchmarks
- [ ] Error handling improvements

### Medium Priority
- [ ] Connection pooling for client
- [ ] Deadline/timeout propagation
- [ ] Interceptors/middleware
- [ ] Metadata helpers
- [ ] Code generation from .proto files

### Nice to Have
- [ ] Service health checking
- [ ] Load balancing
- [ ] Retry policies
- [ ] Circuit breakers
- [ ] Metrics and tracing

## Testing Guidelines

1. **Unit Tests**: Test individual components in isolation
2. **Integration Tests**: Test components working together
3. **Example Tests**: Ensure examples work correctly

Example test structure:
```crystal
require "./spec_helper"

describe MyModule do
  describe ".my_method" do
    context "when given valid input" do
      it "returns expected result" do
        result = MyModule.my_method(valid_input)
        result.should eq(expected_output)
      end
    end

    context "when given invalid input" do
      it "raises an error" do
        expect_raises(ArgumentError) do
          MyModule.my_method(invalid_input)
        end
      end
    end
  end
end
```

## Documentation

- Update README.md if adding user-facing features
- Update ARCHITECTURE.md for architectural changes
- Add inline documentation for public APIs
- Include examples in documentation

## Performance

When working on performance:
- Use `Benchmark.ips` for microbenchmarks
- Profile with `crystal build --release --stats`
- Avoid premature optimization
- Document performance characteristics

## Debugging

Useful debugging techniques:
```crystal
# Print debug information
pp variable

# Inspect types
puts typeof(variable)

# Hex dump binary data
bytes.hexdump

# Enable verbose logging
ENV["DEBUG"] = "1"
```

## Questions?

- Open an issue for questions
- Check existing issues and pull requests
- Read the architecture guide in ARCHITECTURE.md

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
