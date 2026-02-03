#!/bin/bash
# FreshBooks OAuth Setup Script
# Run this once to authenticate and get tokens

set -e

CONFIG_DIR="$HOME/.config/freshbooks"
CREDENTIALS_FILE="$CONFIG_DIR/credentials.json"
TOKENS_FILE="$CONFIG_DIR/tokens.json"

# Create config directory if it doesn't exist
mkdir -p "$CONFIG_DIR"

# Check if credentials file exists
if [ ! -f "$CREDENTIALS_FILE" ]; then
    echo "Error: credentials.json not found!"
    echo "Please create $CREDENTIALS_FILE with:"
    echo '{'
    echo '  "client_id": "YOUR_CLIENT_ID",'
    echo '  "client_secret": "YOUR_CLIENT_SECRET",'
    echo '  "redirect_uri": "https://localhost/callback"'
    echo '}'
    exit 1
fi

# Read credentials (supports 1Password op:// references)
resolve_credential() {
    local value="$1"
    if [[ "$value" == op://* ]]; then
        op read "$value"
    else
        echo "$value"
    fi
}

CLIENT_ID=$(resolve_credential "$(jq -r '.client_id' "$CREDENTIALS_FILE")")
CLIENT_SECRET=$(resolve_credential "$(jq -r '.client_secret' "$CREDENTIALS_FILE")")
REDIRECT_URI=$(jq -r '.redirect_uri' "$CREDENTIALS_FILE")

if [ "$CLIENT_ID" = "YOUR_CLIENT_ID" ] || [ -z "$CLIENT_ID" ]; then
    echo "Error: Please update credentials.json with your actual client_id"
    exit 1
fi

# Function to get authorization URL
get_auth_url() {
    SCOPES="user:profile:read%20user:time_entries:read%20user:time_entries:write%20user:projects:read%20user:clients:read"
    AUTH_URL="https://auth.freshbooks.com/oauth/authorize?client_id=${CLIENT_ID}&response_type=code&redirect_uri=${REDIRECT_URI}&scope=${SCOPES}"
    echo "$AUTH_URL"
}

# Function to exchange code for tokens
exchange_code() {
    local CODE="$1"

    echo "Exchanging code for tokens..."

    RESPONSE=$(curl -s -X POST "https://api.freshbooks.com/auth/oauth/token" \
        -H "Content-Type: application/json" \
        -d "{
            \"grant_type\": \"authorization_code\",
            \"client_id\": \"$CLIENT_ID\",
            \"client_secret\": \"$CLIENT_SECRET\",
            \"code\": \"$CODE\",
            \"redirect_uri\": \"$REDIRECT_URI\"
        }")

    # Check for error
    ERROR=$(echo "$RESPONSE" | jq -r '.error // empty')
    if [ -n "$ERROR" ]; then
        echo "Error: $ERROR"
        echo "Description: $(echo "$RESPONSE" | jq -r '.error_description // empty')"
        exit 1
    fi

    # Save tokens
    echo "$RESPONSE" | jq '{
        access_token: .access_token,
        refresh_token: .refresh_token,
        expires_in: .expires_in,
        created_at: (now | floor)
    }' > "$TOKENS_FILE"

    echo "Tokens saved to $TOKENS_FILE"
    echo "Access token expires in: $(echo "$RESPONSE" | jq -r '.expires_in') seconds"
}

# Function to refresh tokens
refresh_tokens() {
    if [ ! -f "$TOKENS_FILE" ]; then
        echo "Error: No tokens file found. Run 'authorize' first."
        exit 1
    fi

    REFRESH_TOKEN=$(jq -r '.refresh_token' "$TOKENS_FILE")

    echo "Refreshing tokens..."

    RESPONSE=$(curl -s -X POST "https://api.freshbooks.com/auth/oauth/token" \
        -H "Content-Type: application/json" \
        -d "{
            \"grant_type\": \"refresh_token\",
            \"client_id\": \"$CLIENT_ID\",
            \"client_secret\": \"$CLIENT_SECRET\",
            \"refresh_token\": \"$REFRESH_TOKEN\"
        }")

    # Check for error
    ERROR=$(echo "$RESPONSE" | jq -r '.error // empty')
    if [ -n "$ERROR" ]; then
        echo "Error: $ERROR"
        echo "Description: $(echo "$RESPONSE" | jq -r '.error_description // empty')"
        exit 1
    fi

    # Save tokens
    echo "$RESPONSE" | jq '{
        access_token: .access_token,
        refresh_token: .refresh_token,
        expires_in: .expires_in,
        created_at: (now | floor)
    }' > "$TOKENS_FILE"

    echo "Tokens refreshed and saved"
}

# Function to get current user/business info
get_me() {
    if [ ! -f "$TOKENS_FILE" ]; then
        echo "Error: No tokens file found. Run 'authorize' first."
        exit 1
    fi

    ACCESS_TOKEN=$(jq -r '.access_token' "$TOKENS_FILE")

    curl -s "https://api.freshbooks.com/auth/api/v1/users/me" \
        -H "Authorization: Bearer $ACCESS_TOKEN" | jq
}

# Main
case "${1:-}" in
    authorize)
        AUTH_URL=$(get_auth_url)
        echo ""
        echo "=== FreshBooks OAuth Authorization ==="
        echo ""
        echo "1. Open this URL in your browser:"
        echo ""
        echo "$AUTH_URL"
        echo ""
        echo "2. Log in and authorize the app"
        echo ""
        echo "3. You'll be redirected to a page that won't load (that's OK!)"
        echo "   Look at the URL bar - it will look like:"
        echo "   https://localhost/callback?code=XXXXXXX"
        echo ""
        echo "4. Copy the code value and run:"
        echo "   $0 exchange YOUR_CODE_HERE"
        echo ""
        ;;
    exchange)
        if [ -z "${2:-}" ]; then
            echo "Usage: $0 exchange <code>"
            exit 1
        fi
        exchange_code "$2"
        ;;
    refresh)
        refresh_tokens
        ;;
    me)
        get_me
        ;;
    *)
        echo "FreshBooks OAuth Helper"
        echo ""
        echo "Usage: $0 <command>"
        echo ""
        echo "Commands:"
        echo "  authorize  - Get the authorization URL"
        echo "  exchange   - Exchange auth code for tokens"
        echo "  refresh    - Refresh expired tokens"
        echo "  me         - Get current user info (test tokens)"
        echo ""
        ;;
esac
