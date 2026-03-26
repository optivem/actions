# Example Dockerfile for testing the action
# This file is for demonstration purposes only

FROM alpine:latest

# Install a simple web server for testing
RUN apk add --no-cache curl

# Create a simple test file
RUN echo "Hello from Docker!" > /hello.txt

# Set the working directory
WORKDIR /app

# Copy test content
COPY . .

# Default command
CMD ["cat", "/hello.txt"]