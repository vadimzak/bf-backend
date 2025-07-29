#!/bin/bash
# Wrapper script for executing commands on the EC2 instance
# Usage: ./scripts/remote-exec.sh <command>
# Examples:
#   ./scripts/remote-exec.sh "sudo docker ps"
#   ./scripts/remote-exec.sh "cat /var/www/sample-app/deploy/nginx.conf"

set -e

# Configuration
SSH_KEY="$HOME/.ssh/sample-app-key.pem"
SSH_USER="ec2-user"
SSH_HOST="sample.vadimzak.com"

# Check if command is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <command>"
    echo "Execute a command on the remote EC2 instance"
    echo ""
    echo "Examples:"
    echo "  $0 'sudo docker ps'"
    echo "  $0 'ls -la /var/www/'"
    echo "  $0 'sudo docker logs sample-app-nginx-1 --tail 20'"
    exit 1
fi

# Get the command from all arguments
COMMAND="$*"

# Execute the command
ssh -i "$SSH_KEY" "$SSH_USER@$SSH_HOST" "$COMMAND"