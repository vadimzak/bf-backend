#!/bin/bash
# Common functions and variables for Kubernetes scripts

# Cluster configuration
export KOPS_STATE_STORE="s3://bf-kops-state-store"
export CLUSTER_NAME="c02.vadimzak.com"
export AWS_PROFILE="bf"
export AWS_REGION="il-central-1"
export MASTER_SIZE="t4g.medium"
export NODE_SIZE="t4g.medium"
# Docker build platform (ARM64)
export DOCKER_PLATFORM="linux/arm64"
export NODE_COUNT="0"
export DNS_ZONE="vadimzak.com"
export SSH_KEY_PATH="$HOME/.ssh/kops-key"
export K8S_VERSION="1.28.5"
export SETUP_SECONDARY_IP=true

# ECR configuration
export ECR_REGION="il-central-1"

# Logging configuration
# Set LOG_TIMESTAMP_FORMAT to "short" for HH:MM:SS only, or "none" to disable timestamps
export LOG_TIMESTAMP_FORMAT="${LOG_TIMESTAMP_FORMAT:-full}"

# Colors for output
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m' # No Color

# Helper function to format timestamp
get_timestamp() {
    case "${LOG_TIMESTAMP_FORMAT}" in
        "none")
            echo ""
            ;;
        "short")
            echo "[$(date '+%H:%M:%S')] "
            ;;
        *)
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] "
            ;;
    esac
}

# Logging functions
log_info() {
    echo -e "$(get_timestamp)${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "$(get_timestamp)${RED}[ERROR]${NC} $1" >&2
}

log_warning() {
    echo -e "$(get_timestamp)${YELLOW}[WARNING]${NC} $1"
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "$(get_timestamp)${BLUE}[DEBUG]${NC} $1"
    fi
}

# Error handling
set_error_trap() {
    trap 'handle_error $? $LINENO' ERR
}

handle_error() {
    local exit_code=$1
    local line_number=$2
    log_error "Script failed with exit code $exit_code at line $line_number"
    exit $exit_code
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Verify prerequisites
verify_prerequisites() {
    local missing=()
    
    if ! command_exists kubectl; then
        missing+=("kubectl")
    fi
    
    if ! command_exists kops; then
        missing+=("kops")
    fi
    
    if ! command_exists helm; then
        missing+=("helm")
    fi
    
    if ! command_exists aws; then
        missing+=("aws")
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing prerequisites: ${missing[*]}"
        log_error "Please run: scripts/k8s/install-prerequisites.sh"
        return 1
    fi
    
    # Check AWS profile
    if ! aws configure list --profile "$AWS_PROFILE" >/dev/null 2>&1; then
        log_error "AWS profile '$AWS_PROFILE' not configured"
        return 1
    fi
    
    return 0
}

# Wait for condition with timeout
wait_for() {
    local condition="$1"
    local timeout="${2:-300}"  # Default 5 minutes
    local interval="${3:-5}"   # Check every 5 seconds
    local elapsed=0
    
    log_info "Waiting for: $condition (timeout: ${timeout}s)"
    
    while ! eval "$condition"; do
        if [[ $elapsed -ge $timeout ]]; then
            log_error "Timeout waiting for: $condition"
            return 1
        fi
        
        sleep "$interval"
        elapsed=$((elapsed + interval))
        echo -n "."
    done
    
    echo
    log_info "Condition met: $condition"
    return 0
}

# Check if cluster exists
cluster_exists() {
    kops get cluster --name="$CLUSTER_NAME" --state="$KOPS_STATE_STORE" >/dev/null 2>&1
}

# Get cluster status
get_cluster_status() {
    if ! cluster_exists; then
        echo "not_found"
        return 0
    fi
    
    if kubectl get nodes >/dev/null 2>&1; then
        echo "running"
    else
        echo "creating"
    fi
}

# Get master node IP
get_master_ip() {
    aws ec2 describe-instances \
        --filters "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" \
                  "Name=tag:k8s.io/role/master,Values=1" \
                  "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" 2>/dev/null || echo ""
}

# Update DNS record
update_dns_record() {
    local record_name="$1"
    local ip_address="$2"
    local ttl="${3:-300}"
    
    log_info "Updating DNS record: $record_name -> $ip_address"
    
    local change_batch=$(cat <<EOF
{
    "Changes": [{
        "Action": "UPSERT",
        "ResourceRecordSet": {
            "Name": "${record_name}",
            "Type": "A",
            "TTL": ${ttl},
            "ResourceRecords": [{"Value": "${ip_address}"}]
        }
    }]
}
EOF
)
    
    local hosted_zone_id=$(aws route53 list-hosted-zones-by-name \
        --query "HostedZones[?Name=='${DNS_ZONE}.'].Id" \
        --output text \
        --profile "$AWS_PROFILE" | cut -d'/' -f3)
    
    if [[ -z "$hosted_zone_id" ]]; then
        log_error "Could not find hosted zone for $DNS_ZONE"
        return 1
    fi
    
    aws route53 change-resource-record-sets \
        --hosted-zone-id "$hosted_zone_id" \
        --change-batch "$change_batch" \
        --profile "$AWS_PROFILE" >/dev/null
}

# Get ECR registry URL
get_ecr_registry() {
    aws ecr describe-repositories \
        --repository-names sample-app \
        --query 'repositories[0].repositoryUri' \
        --output text \
        --profile "$AWS_PROFILE" \
        --region "$ECR_REGION" 2>/dev/null | cut -d'/' -f1 || echo ""
}

# Create ECR repository if it doesn't exist
ensure_ecr_repository() {
    local repo_name="$1"
    
    if aws ecr describe-repositories \
        --repository-names "$repo_name" \
        --profile "$AWS_PROFILE" \
        --region "$ECR_REGION" >/dev/null 2>&1; then
        log_debug "ECR repository $repo_name already exists"
    else
        log_info "Creating ECR repository: $repo_name"
        aws ecr create-repository \
            --repository-name "$repo_name" \
            --profile "$AWS_PROFILE" \
            --region "$ECR_REGION" >/dev/null
    fi
}

# Docker ECR login
docker_ecr_login() {
    local registry="$1"
    
    log_info "Logging into ECR: $registry"
    aws ecr get-login-password \
        --region "$ECR_REGION" \
        --profile "$AWS_PROFILE" | \
    docker login \
        --username AWS \
        --password-stdin "$registry"
}

# Add security group rule
add_security_group_rule() {
    local port="$1"
    local protocol="${2:-tcp}"
    local cidr="${3:-0.0.0.0/0}"
    
    local sg_id=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=masters.${CLUSTER_NAME}" \
        --query 'SecurityGroups[0].GroupId' \
        --output text \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" 2>/dev/null)
    
    if [[ -z "$sg_id" || "$sg_id" == "None" ]]; then
        log_error "Could not find security group for cluster"
        return 1
    fi
    
    # Check if rule already exists
    if aws ec2 describe-security-groups \
        --group-ids "$sg_id" \
        --query "SecurityGroups[0].IpPermissions[?FromPort==\`$port\` && ToPort==\`$port\` && IpProtocol==\`$protocol\`]" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" | grep -q "$cidr"; then
        log_debug "Security group rule for port $port already exists"
        return 0
    fi
    
    log_info "Adding security group rule: $protocol/$port from $cidr"
    aws ec2 authorize-security-group-ingress \
        --group-id "$sg_id" \
        --protocol "$protocol" \
        --port "$port" \
        --cidr "$cidr" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" >/dev/null
}

# Export all functions
export -f log_info log_error log_warning log_debug
export -f command_exists verify_prerequisites
export -f wait_for cluster_exists get_cluster_status
export -f get_master_ip update_dns_record
export -f get_ecr_registry ensure_ecr_repository docker_ecr_login
export -f add_security_group_rule