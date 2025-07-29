#!/bin/bash
# Deploy sample-app
# This is a convenience wrapper for the main deployment script

# Change to project root
cd "$(dirname "$0")/../.."

# Run the deployment
./scripts/deploy-app.sh sample-app "$@"