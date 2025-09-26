#!/bin/bash

# Source the multi_provider_ai_simple.sh script
source ./multi_provider_ai_simple.sh

echo "Testing spinner functionality..."
echo ""

# Test basic spinner
echo "1. Testing basic spinner for 3 seconds:"
show_spinner "Processing data" 3
echo "✓ Basic spinner test completed"
echo ""

# Create test script to simulate API call with a spinner
cat > ./test_api_call.sh << 'EOF'
#!/bin/bash
# Function to display a simple spinner
show_api_spinner() {
  local message="$1"
  local chars="/-\|"
  local delay=0.2
  echo -n "$message " >&2
  for i in {1..10}; do
    for ((j=0; j<${#chars}; j++)); do
      echo -ne "\b${chars:$j:1}" >&2
      sleep $delay
    done
  done
  echo -ne "\b \b" >&2
  echo "" >&2
}

# Simulate API call
echo -n "⏳ Calling test API..." >&2
show_api_spinner "generating"
echo "✓ Done" >&2
echo '{"message": "This is a test API response"}'
EOF

chmod +x ./test_api_call.sh

# Test simulated API call
echo "2. Testing simulated API call with spinner:"
./test_api_call.sh
echo "✓ API simulation completed"
echo ""

# Clean up
rm ./test_api_call.sh

echo "All tests completed successfully!"
