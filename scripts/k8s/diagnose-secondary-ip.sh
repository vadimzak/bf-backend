#!/bin/bash
set -euo pipefail

# Diagnostic script for secondary IP setup issues

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/k8s-common.sh"

echo "=== Secondary IP Setup Diagnostics ==="
echo

# Check 1: Cluster accessibility
echo "1. Checking cluster accessibility..."
if kubectl get nodes >/dev/null 2>&1; then
    echo "   ✓ Kubectl can access cluster"
    kubectl get nodes
else
    echo "   ✗ Cannot access cluster with kubectl"
    echo "   Run: kops export kubecfg --admin"
    exit 1
fi
echo

# Check 2: Get master IP
echo "2. Getting master node IP..."
master_ip=$(get_master_ip)
if [[ -z "$master_ip" ]]; then
    echo "   ✗ Could not get master IP using AWS tags"
    echo "   Attempting alternative method..."
    
    # Try getting from kubectl
    master_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null || echo "")
    
    if [[ -z "$master_ip" ]]; then
        echo "   ✗ Could not get master IP from kubectl either"
        exit 1
    fi
fi
echo "   ✓ Master IP: $master_ip"
echo

# Check 3: Find instance by IP
echo "3. Finding EC2 instance by IP..."
instance_id=$(aws ec2 describe-instances \
    --filters "Name=network-interface.association.public-ip,Values=$master_ip" \
              "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].InstanceId' \
    --output text \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" 2>&1 || echo "ERROR: $?")

if [[ "$instance_id" == "ERROR:"* ]] || [[ "$instance_id" == "None" ]] || [[ -z "$instance_id" ]]; then
    echo "   ✗ Could not find instance: $instance_id"
    echo "   Checking AWS credentials..."
    aws sts get-caller-identity --profile "$AWS_PROFILE" 2>&1 || echo "   ✗ AWS credentials issue"
    exit 1
fi
echo "   ✓ Instance ID: $instance_id"
echo

# Check 4: Get ENI
echo "4. Getting network interface (ENI)..."
eni_id=$(aws ec2 describe-instances \
    --instance-ids "$instance_id" \
    --query 'Reservations[0].Instances[0].NetworkInterfaces[0].NetworkInterfaceId' \
    --output text \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" 2>&1 || echo "ERROR")

if [[ "$eni_id" == "ERROR" ]] || [[ "$eni_id" == "None" ]] || [[ -z "$eni_id" ]]; then
    echo "   ✗ Could not get ENI: $eni_id"
    exit 1
fi
echo "   ✓ ENI ID: $eni_id"
echo

# Check 5: Check existing secondary IPs
echo "5. Checking for existing secondary IPs..."
secondary_ips=$(aws ec2 describe-network-interfaces \
    --network-interface-ids "$eni_id" \
    --query 'NetworkInterfaces[0].PrivateIpAddresses[?Primary==`false`].PrivateIpAddress' \
    --output text \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" 2>&1 || echo "ERROR")

if [[ "$secondary_ips" == "ERROR" ]]; then
    echo "   ✗ Error checking secondary IPs"
    exit 1
elif [[ -n "$secondary_ips" ]] && [[ "$secondary_ips" != "None" ]]; then
    echo "   ✓ Found existing secondary IP(s): $secondary_ips"
else
    echo "   ℹ No existing secondary IPs"
fi
echo

# Check 6: SSH connectivity
echo "6. Checking SSH connectivity..."
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "ubuntu@$master_ip" "echo 'SSH OK'" >/dev/null 2>&1; then
    echo "   ✓ SSH connection successful"
else
    echo "   ✗ Cannot SSH to master node"
    echo "   Check SSH key: $SSH_KEY_PATH"
    exit 1
fi
echo

# Check 7: Check if HAProxy is installed
echo "7. Checking HAProxy status..."
if ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "ubuntu@$master_ip" "command -v haproxy" >/dev/null 2>&1; then
    echo "   ✓ HAProxy is installed"
    ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "ubuntu@$master_ip" "sudo systemctl is-active haproxy" 2>&1 || echo "   ℹ HAProxy not running"
else
    echo "   ℹ HAProxy not installed (will be installed by setup script)"
fi
echo

# Check 8: Check subnet info
echo "8. Getting subnet information..."
subnet_id=$(aws ec2 describe-instances \
    --instance-ids "$instance_id" \
    --query 'Reservations[0].Instances[0].SubnetId' \
    --output text \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" 2>&1 || echo "ERROR")

if [[ "$subnet_id" != "ERROR" ]] && [[ "$subnet_id" != "None" ]]; then
    subnet_cidr=$(aws ec2 describe-subnets \
        --subnet-ids "$subnet_id" \
        --query 'Subnets[0].CidrBlock' \
        --output text \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" 2>&1 || echo "ERROR")
    echo "   ✓ Subnet: $subnet_id ($subnet_cidr)"
else
    echo "   ✗ Could not get subnet info"
fi
echo

echo "=== Diagnostic Summary ==="
if [[ -n "$secondary_ips" ]] && [[ "$secondary_ips" != "None" ]]; then
    echo "Secondary IP already exists. You can run:"
    echo "  ./scripts/k8s/setup-secondary-ip.sh --force"
    echo "  ./scripts/k8s/setup-haproxy-https.sh"
    echo "  ./scripts/k8s/update-app-dns-secondary.sh"
else
    echo "No secondary IP found. You can run:"
    echo "  ./scripts/k8s/setup-secondary-ip.sh"
    echo "  ./scripts/k8s/setup-haproxy-https.sh"  
    echo "  ./scripts/k8s/update-app-dns-secondary.sh"
fi
echo
echo "Or bootstrap a new cluster without secondary IP:"
echo "  ./scripts/k8s/teardown-cluster.sh"
echo "  ./scripts/k8s/bootstrap-cluster.sh --no-secondary-ip"