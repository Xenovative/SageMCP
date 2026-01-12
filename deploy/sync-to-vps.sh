#!/bin/bash
# Sage MCP - Sync to VPS Script (Linux/macOS)
# Usage: ./deploy/sync-to-vps.sh user@your-vps.com

set -e

# Configuration
VPS_HOST="${1:-}"
VPS_PATH="${2:-/opt/sage-mcp}"
SSH_KEY="${SSH_KEY:-}"
INCLUDE_DB="${INCLUDE_DB:-false}"
RESTART="${RESTART:-false}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

if [ -z "$VPS_HOST" ]; then
    echo -e "${RED}Usage: $0 user@your-vps.com [/opt/sage-mcp]${NC}"
    echo ""
    echo "Environment variables:"
    echo "  SSH_KEY=/path/to/key    - SSH private key"
    echo "  INCLUDE_DB=true         - Include database in sync"
    echo "  RESTART=true            - Restart service after sync"
    exit 1
fi

echo -e "${CYAN}==========================================${NC}"
echo -e "${CYAN}  Sage MCP - Sync to VPS${NC}"
echo -e "${CYAN}==========================================${NC}"
echo ""

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_PATH="$(dirname "$SCRIPT_DIR")"

echo "Local path: $LOCAL_PATH"
echo "VPS target: ${VPS_HOST}:${VPS_PATH}"
echo ""

# Build SSH options
SSH_OPTS="-o StrictHostKeyChecking=no"
if [ -n "$SSH_KEY" ]; then
    SSH_OPTS="$SSH_OPTS -i $SSH_KEY"
fi

# Rsync excludes
EXCLUDES=(
    --exclude='node_modules'
    --exclude='.git'
    --exclude='*.log'
    --exclude='.env'
    --exclude='.env.local'
)

if [ "$INCLUDE_DB" != "true" ]; then
    EXCLUDES+=(
        --exclude='data/sage.db'
        --exclude='data/sage.db-journal'
        --exclude='data/sage.db-wal'
    )
fi

echo -e "${YELLOW}Syncing source files...${NC}"

rsync -avz --progress \
    "${EXCLUDES[@]}" \
    -e "ssh $SSH_OPTS" \
    "$LOCAL_PATH/" \
    "${VPS_HOST}:${VPS_PATH}/src/"

# Sync database if requested
if [ "$INCLUDE_DB" = "true" ]; then
    echo ""
    echo -e "${YELLOW}Syncing database...${NC}"
    
    if [ -f "$LOCAL_PATH/data/sage.db" ]; then
        scp $SSH_OPTS "$LOCAL_PATH/data/sage.db" "${VPS_HOST}:${VPS_PATH}/data/"
    else
        echo -e "${RED}Database not found at $LOCAL_PATH/data/sage.db${NC}"
    fi
fi

# Install and build on VPS
echo ""
echo -e "${YELLOW}Installing dependencies and building on VPS...${NC}"

ssh $SSH_OPTS "$VPS_HOST" << EOF
cd ${VPS_PATH}/src
npm install --production=false
npm run build
sudo chown -R sage:sage ${VPS_PATH} 2>/dev/null || true
EOF

# Restart if requested
if [ "$RESTART" = "true" ]; then
    echo ""
    echo -e "${YELLOW}Restarting service...${NC}"
    ssh $SSH_OPTS "$VPS_HOST" "sudo systemctl restart sage-mcp"
    
    sleep 2
    
    echo -e "${YELLOW}Service status:${NC}"
    ssh $SSH_OPTS "$VPS_HOST" "sudo systemctl status sage-mcp --no-pager" || true
fi

echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}  Sync Complete!${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo "Next steps:"
echo "  - Start service:   ssh $VPS_HOST 'sudo systemctl start sage-mcp'"
echo "  - Check status:    ssh $VPS_HOST 'sudo systemctl status sage-mcp'"
echo "  - View logs:       ssh $VPS_HOST 'sudo journalctl -u sage-mcp -f'"
