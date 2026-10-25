#!/usr/bin/env bash
echo "Stopping WATTSON services..."
pkill -f "uvicorn wattson.api.app:app" 2>/dev/null || true
pkill -f "wattson.worker" 2>/dev/null || true
pkill -f "temporal server start-dev" 2>/dev/null || true
pkill -f "next-server" 2>/dev/null || true
pkill -f "next dev" 2>/dev/null || true
echo "Stopped."
