#!/bin/bash

# Cover Generation Script
# Automates the generation of front and back covers using ChatGPT or Gemini
# Requires: playwright, jq (for JSON parsing)

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COVERS_DIR="${SCRIPT_DIR}/covers"
CONFIG_FILE="${SCRIPT_DIR}/.cover-config.json"
DEFAULT_SERVICE="chatgpt"  # or "gemini"
DOWNLOAD_WAIT_TIME=30      # seconds to wait for download

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check dependencies
check_dependencies() {
    print_status "Checking dependencies..."
    
    if ! command -v playwright &> /dev/null; then
        print_error "Playwright is not installed. Installing..."
        pip install playwright
        playwright install chromium
    fi
    
    if ! command -v jq &> /dev/null; then
        print_error "jq is required but not installed. Please install jq."
        exit 1
    fi
}

# Create necessary directories
setup_directories() {
    mkdir -p "$COVERS_DIR"
    mkdir -p "${COVERS_DIR}/front"
    mkdir -p "${COVERS_DIR}/back"
}

# Load configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        SERVICE=$(jq -r '.service // "chatgpt"' "$CONFIG_FILE")
        USERNAME=$(jq -r '.username // ""' "$CONFIG_FILE")
        PASSWORD=$(jq -r '.password // ""' "$CONFIG_FILE")
        BOOK_TITLE=$(jq -r '.book_title // ""' "$CONFIG_FILE")
        AUTHOR_NAME=$(jq -r '.author_name // ""' "$CONFIG_FILE")
        GENRE=$(jq -r '.genre // ""' "$CONFIG_FILE")
    else
        SERVICE="$DEFAULT_SERVICE"
        USERNAME=""
        PASSWORD=""
        BOOK_TITLE=""
        AUTHOR_NAME=""
        GENRE=""
    fi
}

# Save configuration
save_config() {
    cat > "$CONFIG_FILE" << EOF
{
    "service": "$SERVICE",
    "username": "$USERNAME",
    "password": "$PASSWORD",
    "book_title": "$BOOK_TITLE",
    "author_name": "$AUTHOR_NAME",
    "genre": "$GENRE"
}
EOF
}

# Get user input for configuration
configure_settings() {
    print_status "Configuring cover generation settings..."
    
    echo "Select image generation service:"
    echo "1) ChatGPT (DALL-E)"
    echo "2) Google Gemini"
    read -p "Enter choice (1-2) [default: 1]: " service_choice
    
    case $service_choice in
        2) SERVICE="gemini" ;;
        *) SERVICE="chatgpt" ;;
    esac
    
    read -p "Enter your username/email: " USERNAME
    read -s -p "Enter your password: " PASSWORD
    echo
    
    read -p "Enter book title: " BOOK_TITLE
    read -p "Enter author name: " AUTHOR_NAME
    read -p "Enter book genre: " GENRE
    
    save_config
    print_success "Configuration saved!"
}

# Generate prompts for covers
generate_prompts() {
    local cover_type="$1"
    
    if [[ "$cover_type" == "front" ]]; then
        cat << EOF
Create a professional book cover design for "${BOOK_TITLE}" by ${AUTHOR_NAME}. 
Genre: ${GENRE}
Style: Modern, eye-catching, commercial book cover
Requirements:
- High resolution (300 DPI minimum)
- Professional typography placement area for title and author
- Compelling visual elements that represent the ${GENRE} genre
- Market-appropriate color scheme
- No text overlay (text will be added separately)
- Aspect ratio: 6:9 (typical book cover proportions)
EOF
    else
        cat << EOF
Create a professional book back cover design for "${BOOK_TITLE}" by ${AUTHOR_NAME}.
Genre: ${GENRE}
Requirements:
- High resolution (300 DPI minimum)
- Clean, minimalist design complementing the front cover
- Space for book description/synopsis
- Space for author bio
- Space for barcode (bottom right)
- Professional layout with good typography spacing
- Matching color scheme to front cover
- Aspect ratio: 6:9
EOF
    fi
}

# ChatGPT automation script
generate_chatgpt_cover() {
    local cover_type="$1"
    local prompt="$2"
    local output_file="$3"
    
    cat > "/tmp/chatgpt_automation.py" << 'EOF'
import asyncio
from playwright.async_api import async_playwright
import sys
import os
import time

async def generate_image(cover_type, prompt, output_file, username, password):
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=False)  # Set to True for headless
        context = await browser.new_context()
        page = await context.new_page()
        
        try:
            # Navigate to ChatGPT
            await page.goto("https://chat.openai.com/")
            await page.wait_for_load_state('networkidle')
            
            # Check if already logged in
            login_button = page.locator('button:has-text("Log in")')
            if await login_button.count() > 0:
                print("Logging in to ChatGPT...")
                await login_button.click()
                
                # Enter credentials
                await page.fill('input[name="username"]', username)
                await page.click('button[type="submit"]')
                await page.wait_for_timeout(1000)
                
                await page.fill('input[name="password"]', password)
                await page.click('button[type="submit"]')
                await page.wait_for_load_state('networkidle')
            
            # Start new conversation
            new_chat = page.locator('button:has-text("New chat")')
            if await new_chat.count() > 0:
                await new_chat.click()
            
            # Enter the prompt
            textarea = page.locator('textarea[placeholder*="Message"]')
            await textarea.fill(prompt)
            await textarea.press('Enter')
            
            # Wait for response and image generation
            print("Waiting for image generation...")
            await page.wait_for_timeout(30000)  # Wait 30 seconds
            
            # Look for generated image
            img_selector = 'img[alt*="Generated image"]'
            await page.wait_for_selector(img_selector, timeout=60000)
            
            # Download image
            images = page.locator(img_selector)
            if await images.count() > 0:
                # Right-click and save image
                await images.first.click(button="right")
                await page.locator('text="Save image as"').click()
                
                # Handle download dialog (this varies by OS)
                await page.wait_for_timeout(2000)
                print(f"Image generated and ready for download to {output_file}")
                
                # Note: Actual file download handling depends on browser settings
                # Manual intervention might be needed here
                
        except Exception as e:
            print(f"Error: {e}")
        finally:
            await browser.close()

if __name__ == "__main__":
    cover_type, prompt, output_file, username, password = sys.argv[1:6]
    asyncio.run(generate_image(cover_type, prompt, output_file, username, password))
EOF

    python3 /tmp/chatgpt_automation.py "$cover_type" "$prompt" "$output_file" "$USERNAME" "$PASSWORD"
}

# Gemini automation script
generate_gemini_cover() {
    local cover_type="$1"
    local prompt="$2"
    local output_file="$3"
    
    cat > "/tmp/gemini_automation.py" << 'EOF'
import asyncio
from playwright.async_api import async_playwright
import sys
import os
import time

async def generate_image(cover_type, prompt, output_file, username, password):
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=False)
        context = await browser.new_context()
        page = await context.new_page()
        
        try:
            # Navigate to Gemini
            await page.goto("https://gemini.google.com/")
            await page.wait_for_load_state('networkidle')
            
            # Handle login if needed
            sign_in = page.locator('text="Sign in"')
            if await sign_in.count() > 0:
                await sign_in.click()
                await page.fill('input[type="email"]', username)
                await page.click('button:has-text("Next")')
                await page.wait_for_timeout(2000)
                
                await page.fill('input[type="password"]', password)
                await page.click('button:has-text("Next")')
                await page.wait_for_load_state('networkidle')
            
            # Enter the prompt
            textarea = page.locator('textarea')
            await textarea.fill(f"Generate an image: {prompt}")
            await textarea.press('Enter')
            
            # Wait for image generation
            print("Waiting for image generation...")
            await page.wait_for_timeout(30000)
            
            # Look for generated image and download
            img_selector = 'img[src*="googleusercontent"]'
            await page.wait_for_selector(img_selector, timeout=60000)
            
            images = page.locator(img_selector)
            if await images.count() > 0:
                await images.first.click(button="right")
                await page.locator('text="Save image as"').click()
                await page.wait_for_timeout(2000)
                print(f"Image generated for {cover_type} cover")
                
        except Exception as e:
            print(f"Error: {e}")
        finally:
            await browser.close()

if __name__ == "__main__":
    cover_type, prompt, output_file, username, password = sys.argv[1:6]
    asyncio.run(generate_image(cover_type, prompt, output_file, username, password))
EOF

    python3 /tmp/gemini_automation.py "$cover_type" "$prompt" "$output_file" "$USERNAME" "$PASSWORD"
}

# Generate covers
generate_covers() {
    print_status "Generating book covers..."
    
    # Generate front cover
    print_status "Generating front cover..."
    front_prompt=$(generate_prompts "front")
    front_output="${COVERS_DIR}/front/${BOOK_TITLE// /_}_front_cover.png"
    
    if [[ "$SERVICE" == "chatgpt" ]]; then
        generate_chatgpt_cover "front" "$front_prompt" "$front_output"
    else
        generate_gemini_cover "front" "$front_prompt" "$front_output"
    fi
    
    print_success "Front cover generation initiated"
    
    # Wait before generating back cover
    sleep 5
    
    # Generate back cover
    print_status "Generating back cover..."
    back_prompt=$(generate_prompts "back")
    back_output="${COVERS_DIR}/back/${BOOK_TITLE// /_}_back_cover.png"
    
    if [[ "$SERVICE" == "chatgpt" ]]; then
        generate_chatgpt_cover "back" "$back_prompt" "$back_output"
    else
        generate_gemini_cover "back" "$back_prompt" "$back_output"
    fi
    
    print_success "Back cover generation initiated"
}

# Show help
show_help() {
    cat << EOF
Cover Generation Script

Usage: $0 [OPTIONS]

Options:
    -c, --configure     Configure settings (service, credentials, book info)
    -g, --generate      Generate both front and back covers
    -f, --front-only    Generate front cover only
    -b, --back-only     Generate back cover only
    -s, --service       Set service (chatgpt|gemini)
    -h, --help          Show this help message

Examples:
    $0 --configure              # Set up credentials and book info
    $0 --generate               # Generate both covers
    $0 --front-only             # Generate front cover only
    $0 --service chatgpt -g     # Use ChatGPT to generate covers

EOF
}

# Main function
main() {
    check_dependencies
    setup_directories
    load_config
    
    case "$1" in
        -c|--configure)
            configure_settings
            ;;
        -g|--generate)
            if [[ -z "$USERNAME" || -z "$BOOK_TITLE" ]]; then
                print_error "Configuration required. Run with --configure first."
                exit 1
            fi
            generate_covers
            ;;
        -f|--front-only)
            if [[ -z "$USERNAME" || -z "$BOOK_TITLE" ]]; then
                print_error "Configuration required. Run with --configure first."
                exit 1
            fi
            print_status "Generating front cover only..."
            front_prompt=$(generate_prompts "front")
            front_output="${COVERS_DIR}/front/${BOOK_TITLE// /_}_front_cover.png"
            if [[ "$SERVICE" == "chatgpt" ]]; then
                generate_chatgpt_cover "front" "$front_prompt" "$front_output"
            else
                generate_gemini_cover "front" "$front_prompt" "$front_output"
            fi
            ;;
        -b|--back-only)
            if [[ -z "$USERNAME" || -z "$BOOK_TITLE" ]]; then
                print_error "Configuration required. Run with --configure first."
                exit 1
            fi
            print_status "Generating back cover only..."
            back_prompt=$(generate_prompts "back")
            back_output="${COVERS_DIR}/back/${BOOK_TITLE// /_}_back_cover.png"
            if [[ "$SERVICE" == "chatgpt" ]]; then
                generate_chatgpt_cover "back" "$back_prompt" "$back_output"
            else
                generate_gemini_cover "back" "$back_prompt" "$back_output"
            fi
            ;;
        -s|--service)
            if [[ -n "$2" ]]; then
                if [[ "$2" == "chatgpt" || "$2" == "gemini" ]]; then
                    SERVICE="$2"
                    save_config
                    print_success "Service set to $SERVICE"
                else
                    print_error "Invalid service. Use 'chatgpt' or 'gemini'"
                    exit 1
                fi
            else
                print_error "Service name required"
                exit 1
            fi
            ;;
        -h|--help|*)
            show_help
            ;;
    esac
}

# Check if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi