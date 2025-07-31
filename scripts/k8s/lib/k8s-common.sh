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
    local apply_lifecycle="${2:-true}"
    
    if aws ecr describe-repositories \
        --repository-names "$repo_name" \
        --profile "$AWS_PROFILE" \
        --region "$ECR_REGION" >/dev/null 2>&1; then
        log_debug "ECR repository $repo_name already exists"
        
        # Apply lifecycle policy to existing repository if requested
        if [[ "$apply_lifecycle" == "true" ]]; then
            create_ecr_lifecycle_policy "$repo_name" 10
        fi
    else
        log_info "Creating ECR repository: $repo_name"
        aws ecr create-repository \
            --repository-name "$repo_name" \
            --profile "$AWS_PROFILE" \
            --region "$ECR_REGION" >/dev/null
        
        # Apply lifecycle policy to new repository
        if [[ "$apply_lifecycle" == "true" ]]; then
            create_ecr_lifecycle_policy "$repo_name" 10
        fi
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

# Delete ECR repository
delete_ecr_repository() {
    local repo_name="$1"
    local force="${2:-false}"
    
    if ! aws ecr describe-repositories \
        --repository-names "$repo_name" \
        --profile "$AWS_PROFILE" \
        --region "$ECR_REGION" >/dev/null 2>&1; then
        log_debug "ECR repository $repo_name does not exist"
        return 0
    fi
    
    log_info "Deleting ECR repository: $repo_name"
    
    if [[ "$force" == "true" ]]; then
        # Force delete with all images
        aws ecr delete-repository \
            --repository-name "$repo_name" \
            --force \
            --profile "$AWS_PROFILE" \
            --region "$ECR_REGION" >/dev/null
    else
        # Delete only if empty
        aws ecr delete-repository \
            --repository-name "$repo_name" \
            --profile "$AWS_PROFILE" \
            --region "$ECR_REGION" >/dev/null
    fi
}

# List all ECR repositories
list_ecr_repositories() {
    aws ecr describe-repositories \
        --query 'repositories[].repositoryName' \
        --output text \
        --profile "$AWS_PROFILE" \
        --region "$ECR_REGION" 2>/dev/null || echo ""
}

# Create ECR lifecycle policy to keep only last N images
create_ecr_lifecycle_policy() {
    local repo_name="$1"
    local keep_count="${2:-10}"
    
    log_info "Creating ECR lifecycle policy for $repo_name (keep last $keep_count images)"
    
    local policy_json=$(cat <<EOF
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Keep only last $keep_count images",
      "selection": {
        "tagStatus": "any",
        "countType": "imageCountMoreThan",
        "countNumber": $keep_count
      },
      "action": {
        "type": "expire"
      }
    }
  ]
}
EOF
)
    
    aws ecr put-lifecycle-policy \
        --repository-name "$repo_name" \
        --lifecycle-policy-text "$policy_json" \
        --profile "$AWS_PROFILE" \
        --region "$ECR_REGION" >/dev/null
}

# Apply lifecycle policies to all app ECR repositories
apply_ecr_lifecycle_policies() {
    local keep_count="${1:-10}"
    
    log_info "Applying ECR lifecycle policies (keep last $keep_count images)..."
    
    # Get all ECR repositories
    local repos=$(list_ecr_repositories)
    
    for repo in $repos; do
        # Only apply to app repositories (not system repositories)
        if [[ -d "$(cd "$SCRIPT_DIR/../.." && pwd)/apps/$repo" ]]; then
            create_ecr_lifecycle_policy "$repo" "$keep_count"
        fi
    done
}

# Clean up old ECR images manually (immediate cleanup)
cleanup_old_ecr_images() {
    local repo_name="$1"
    local keep_count="${2:-10}"
    local dry_run="${3:-false}"
    
    log_info "Cleaning up old images in ECR repository: $repo_name (keep last $keep_count)"
    
    # Get image details sorted by image pushed date
    local images=$(aws ecr describe-images \
        --repository-name "$repo_name" \
        --query 'sort_by(imageDetails,&imagePushedAt)[:-'$keep_count'].imageDigest' \
        --output text \
        --profile "$AWS_PROFILE" \
        --region "$ECR_REGION" 2>/dev/null)
    
    if [[ -z "$images" ]] || [[ "$images" == "None" ]]; then
        log_info "No old images to clean up in $repo_name"
        return 0
    fi
    
    local image_count=$(echo "$images" | wc -w)
    
    if [[ "$dry_run" == "true" ]]; then
        log_info "DRY RUN: Would delete $image_count old images from $repo_name"
        return 0
    fi
    
    log_info "Deleting $image_count old images from $repo_name..."
    
    for digest in $images; do
        aws ecr batch-delete-image \
            --repository-name "$repo_name" \
            --image-ids imageDigest="$digest" \
            --profile "$AWS_PROFILE" \
            --region "$ECR_REGION" >/dev/null
    done
    
    log_info "Cleaned up $image_count old images from $repo_name"
}

# Delete all app ECR repositories
delete_app_ecr_repositories() {
    local apps="${1:-}"
    local force="${2:-false}"
    
    if [[ -z "$apps" ]]; then
        # Auto-detect apps by finding deploy.config files
        local project_root="$(cd "$SCRIPT_DIR/../.." && pwd)"
        apps=$(find "$project_root/apps" -name "deploy.config" -type f | \
            while read -r config; do
                basename "$(dirname "$config")"
            done)
    fi
    
    if [[ -z "$apps" ]]; then
        log_warning "No apps found to clean up ECR repositories"
        return 0
    fi
    
    log_info "Cleaning up ECR repositories for apps: $apps"
    
    for app in $apps; do
        delete_ecr_repository "$app" "$force"
    done
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

# IAM helper functions for per-app security

# Check if IAM role exists for an app
iam_role_exists() {
    local app_name="$1"
    local role_name="${app_name}-app-role"
    
    aws iam get-role --role-name "$role_name" --profile "$AWS_PROFILE" >/dev/null 2>&1
}

# Check if IAM setup exists for an app
check_iam_setup() {
    local app_name="$1"
    local project_root="${2:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
    local iam_dir="$project_root/apps/$app_name/aws/iam"
    
    # Check if IAM directory and files exist
    if [[ ! -d "$iam_dir" ]]; then
        log_warning "IAM directory not found for $app_name: $iam_dir"
        return 1
    fi
    
    local required_files=("setup-iam.sh" "permissions-policy.json" "role-policy.json" "local-dev-setup.sh")
    for file in "${required_files[@]}"; do
        if [[ ! -f "$iam_dir/$file" ]]; then
            log_warning "Missing IAM file for $app_name: $iam_dir/$file"
            return 1
        fi
    done
    
    # Check if IAM role exists in AWS
    if ! iam_role_exists "$app_name"; then
        log_warning "IAM role not found in AWS for $app_name"
        return 1
    fi
    
    log_info "✅ IAM setup verified for $app_name"
    return 0
}

# Setup IAM role for an app
setup_app_iam() {
    local app_name="$1"
    local project_root="${2:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
    local iam_script="$project_root/apps/$app_name/aws/iam/setup-iam.sh"
    
    if [[ ! -f "$iam_script" ]]; then
        log_error "IAM setup script not found: $iam_script"
        log_error "Please create IAM infrastructure for $app_name first"
        return 1
    fi
    
    log_info "🔧 Setting up IAM role for $app_name..."
    if ! "$iam_script"; then
        log_error "Failed to setup IAM role for $app_name"
        return 1
    fi
    
    log_info "✅ IAM role setup completed for $app_name"
    return 0
}

# Version management functions

# Get current version from package.json
get_app_version() {
    local app_name="$1"
    local project_root="${2:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
    local package_json="$project_root/apps/$app_name/package.json"
    
    if [[ -f "$package_json" ]]; then
        node -p "require('$package_json').version" 2>/dev/null || echo "1.0.0"
    else
        echo "1.0.0"
    fi
}

# Bump version in package.json
bump_app_version() {
    local app_name="$1"
    local bump_type="${2:-patch}"  # patch, minor, major
    local project_root="${3:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
    local app_dir="$project_root/apps/$app_name"
    
    if [[ ! -f "$app_dir/package.json" ]]; then
        log_error "package.json not found for $app_name"
        return 1
    fi
    
    local old_version=$(get_app_version "$app_name" "$project_root")
    
    # Use npm version to bump version
    cd "$app_dir"
    local new_version=$(npm version "$bump_type" --no-git-tag-version 2>/dev/null | tr -d 'v')
    cd - >/dev/null
    
    if [[ -n "$new_version" ]]; then
        log_info "📈 Version bumped: $app_name $old_version → $new_version ($bump_type)"
        echo "$new_version"
    else
        log_error "Failed to bump version for $app_name"
        return 1
    fi
}

# Create version info for deployment
create_version_info() {
    local app_name="$1"
    local project_root="${2:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
    local version=$(get_app_version "$app_name" "$project_root")
    local git_commit=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    local build_time=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    local deployed_by=$(whoami)
    
    export APP_VERSION="$version"
    export APP_GIT_COMMIT="$git_commit"
    export APP_BUILD_TIME="$build_time"
    export APP_DEPLOYED_BY="$deployed_by"
    
    log_info "📦 Version info: $app_name v$version (commit: $git_commit, built: $build_time)"
}

# Validate deployment prerequisites including IAM
validate_deployment_prerequisites() {
    local app_name="$1"
    local project_root="${2:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
    
    log_info "🔍 Validating deployment prerequisites for $app_name..."
    
    # Check basic prerequisites
    if ! verify_prerequisites; then
        return 1
    fi
    
    # Check cluster connection
    if ! kubectl get nodes >/dev/null 2>&1; then
        log_error "Cannot connect to Kubernetes cluster"
        log_error "Run ./scripts/k8s/bootstrap-cluster.sh first"
        return 1
    fi
    
    # Check IAM setup
    if ! check_iam_setup "$app_name" "$project_root"; then
        log_warning "IAM setup issues detected for $app_name"
        log_info "You can run: apps/$app_name/aws/iam/setup-iam.sh"
        # Don't fail deployment for IAM issues, just warn
    fi
    
    # Check if service account exists
    if kubectl get serviceaccount "${app_name}-service-account" -n apps >/dev/null 2>&1; then
        log_info "✅ Service account found for $app_name"
    else
        log_warning "Service account not found for $app_name, will be created during deployment"
    fi
    
    log_info "✅ Prerequisites validation completed for $app_name"
    return 0
}

# Export all functions
export -f log_info log_error log_warning log_debug
export -f command_exists verify_prerequisites
export -f wait_for cluster_exists get_cluster_status
export -f get_master_ip update_dns_record
export -f get_ecr_registry ensure_ecr_repository docker_ecr_login delete_ecr_repository list_ecr_repositories delete_app_ecr_repositories
export -f add_security_group_rule
export -f iam_role_exists check_iam_setup setup_app_iam validate_deployment_prerequisites