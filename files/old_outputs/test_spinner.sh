#!/bin/bash

# Test script to demonstrate the spinner functionality

echo "🧪 Testing the spinner functionality..."
echo ""

# Source the multi-provider script
source multi_provider_ai_simple.sh

echo "Test 1: Quick API call (should NOT show spinner)"
echo "----------------------------------------"
smart_api_call "Hello" "You are helpful" "general" 0.7 20

echo ""
echo ""
echo "Test 2: Longer API call (should show spinner after 2 seconds)"
echo "--------------------------------------------------------"
smart_api_call "Write a detailed 300-word article about the benefits of renewable energy, including solar, wind, and hydroelectric power. Discuss environmental impact, economic advantages, and future prospects." "You are an environmental expert and technical writer." "general" 0.7 2000

echo ""
echo "✅ Spinner tests completed!"
