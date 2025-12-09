# ============================================================================
# MCP Calculator Server - Dockerfile
# ============================================================================
# Multi-stage build for minimal final image
# ============================================================================

FROM python:3.12-slim as builder

# Set working directory
WORKDIR /build

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# ============================================================================
# Final Stage
# ============================================================================

FROM python:3.12-slim

# Set working directory
WORKDIR /app

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy Python dependencies from builder
COPY --from=builder /root/.local /root/.local

# Copy application code
COPY server.py .

# Create non-root user (required by OPA policy: runAsUser 1000)
RUN useradd -m -u 1000 -s /bin/bash mcpuser && \
    chown -R mcpuser:mcpuser /app && \
    chmod +x server.py

# Make sure scripts in .local are usable
ENV PATH=/root/.local/bin:$PATH

# Switch to non-root user
USER 1000

# Expose MCP server port
EXPOSE 8080

# Health check (Kubernetes will use /health and /ready endpoints)
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Set Python to run in unbuffered mode (better for container logging)
ENV PYTHONUNBUFFERED=1

# Run MCP server
CMD ["python", "server.py"]
