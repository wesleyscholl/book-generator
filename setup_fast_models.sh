#!/bin/bash

# Quick setup script for fast Ollama models on M3 MacBook Air
# These models are optimized for speed and efficiency

echo "🚀 Setting up fast Ollama models for M3 MacBook Air..."

# Check if Ollama is running
if ! command -v ollama >/dev/null 2>&1; then
    echo "❌ Ollama is not installed. Please install it first:"
    echo "   curl -fsSL https://ollama.ai/install.sh | sh"
    exit 1
fi

# List of fast models optimized for M3 MacBook Air
FAST_MODELS=(
    "llama3.2:1b"      # 1.3GB - Ultra fast, good for quick tasks
    "llama3.2:3b"      # 2.0GB - Balanced speed/quality
    "qwen2.5:1.5b"     # 986MB - Very fast, excellent for coding
    "qwen2.5:3b"       # 1.9GB - Good balance, strong reasoning
    "gemma2:2b"        # 1.6GB - Fast and efficient
    "phi3.5:3.8b"      # 2.2GB - Microsoft model, good quality
)

echo ""
echo "📋 Fast Models for M3 MacBook Air:"
echo "────────────────────────────────────────────"

for model in "${FAST_MODELS[@]}"; do
    echo "Checking $model..."
    
    if ollama list | grep -q "$model"; then
        echo "✅ $model - Already installed"
    else
        echo "📥 Installing $model..."
        if ollama pull "$model"; then
            echo "✅ $model - Successfully installed"
        else
            echo "❌ $model - Failed to install"
        fi
    fi
    echo ""
done

echo "🎉 Setup complete!"
echo ""
echo "💡 Model Recommendations for M3 MacBook Air:"
echo "   🏃‍♂️ Ultra Fast: llama3.2:1b, qwen2.5:1.5b"
echo "   ⚡ Fast: gemma2:2b, llama3.2:3b"
echo "   🔄 Balanced: qwen2.5:3b, phi3.5:3.8b"
echo ""
echo "🔧 Usage Tips:"
echo "   - These models use 8-16GB RAM typically"
echo "   - Response time: 0.5-3 seconds per response"
echo "   - Perfect for book generation workflows"
echo "   - Can run multiple models simultaneously"
echo ""
echo "🧪 Test the setup:"
echo "   ./multi_provider_ai.sh test"
