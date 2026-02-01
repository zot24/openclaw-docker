#!/bin/bash
# Local validation script - run before creating PRs
# Usage: ./test.sh

set -e

BASE_IMAGE="ghcr.io/zot24/openclaw-base:latest"
IMAGE_NAME="openclaw:test"
CONTAINER_NAME="openclaw-test-$$"

echo "=== OpenClaw Docker Local Validation ==="
echo ""

# Step 1: Check/build base image
echo "[1/4] Checking base image..."
if ! docker image inspect "$BASE_IMAGE" > /dev/null 2>&1; then
    echo "Base image not found locally. Building from Dockerfile.base..."
    echo "(This is slow the first time, but cached afterwards)"
    echo ""
    if ! docker build -f Dockerfile.base -t "$BASE_IMAGE" . ; then
        echo "FAIL: Base image build failed"
        exit 1
    fi
    echo ""
    echo "OK: Base image built successfully"
else
    echo "OK: Base image exists locally"
fi
echo ""

# Step 2: Build the main image
echo "[2/4] Building main image..."
if ! docker build -t "$IMAGE_NAME" . ; then
    echo "FAIL: Docker build failed"
    exit 1
fi
echo "OK: Image built successfully"
echo ""

# Step 3: Run container and validate startup
echo "[3/4] Starting container..."
docker run -d --name "$CONTAINER_NAME" -p 18799:18789 "$IMAGE_NAME" > /dev/null

# Wait for startup (gateway can take 15-20s to fully initialize)
echo "Waiting for gateway to start..."
for i in {1..30}; do
    sleep 2
    LOGS=$(docker logs "$CONTAINER_NAME" 2>&1)

    # Check for config errors first
    if echo "$LOGS" | grep -q "Invalid config"; then
        echo "FAIL: Config validation error detected"
        echo ""
        echo "--- Logs ---"
        echo "$LOGS"
        docker stop "$CONTAINER_NAME" > /dev/null 2>&1 || true
        docker rm "$CONTAINER_NAME" > /dev/null 2>&1 || true
        exit 1
    fi

    # Check if gateway started
    if echo "$LOGS" | grep -q "\[gateway\] listening"; then
        echo "OK: Gateway started successfully"
        break
    fi

    if [ $i -eq 30 ]; then
        echo "FAIL: Gateway did not start within 60s timeout"
        echo ""
        echo "--- Logs ---"
        echo "$LOGS"
        docker stop "$CONTAINER_NAME" > /dev/null 2>&1 || true
        docker rm "$CONTAINER_NAME" > /dev/null 2>&1 || true
        exit 1
    fi
done

# Step 4: Final validation
echo "[4/4] Validating services..."

# Check WebChat UI is accessible
if curl -s -o /dev/null -w "%{http_code}" http://localhost:18799/chat | grep -q "200"; then
    echo "OK: WebChat UI accessible"
else
    echo "WARN: WebChat UI not accessible (may need more time)"
fi

# Cleanup
echo ""
echo "Cleaning up..."
docker stop "$CONTAINER_NAME" > /dev/null 2>&1
docker rm "$CONTAINER_NAME" > /dev/null 2>&1

echo ""
echo "=== PASSED ==="
echo "Image is ready for PR"
