#!/bin/bash
set -euo pipefail

# Teardown Kubernetes cluster created with KOPS
# This script safely removes all K8s resources

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/k8s-common.sh"

# Set error handling
set_error_trap

# Script options
FORCE=false
DELETE_STATE_STORE=false
DELETE_LOCAL_CONFIG=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE=true
            shift
            ;;
        --delete-state-store)
            DELETE_STATE_STORE=true
            shift
            ;;
        --delete-local-config)
            DELETE_LOCAL_CONFIG=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --force              Skip confirmation prompts"
            echo "  --delete-state-store Delete S3 state store bucket"
            echo "  --delete-local-config Delete local SSH keys and kubeconfig"
            echo "  --help               Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Confirm teardown
confirm_teardown() {
    if [[ "$FORCE" == "true" ]]; then
        return 0
    fi
    
    echo
    log_warning "This will delete the Kubernetes cluster: $CLUSTER_NAME"
    log_warning "All applications and data will be lost!"
    echo
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! "$REPLY" =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Teardown cancelled"
        exit 0
    fi
}

# Delete applications
delete_applications() {
    log_info "Deleting applications..."
    
    if ! kubectl get nodes >/dev/null 2>&1; then
        log_warning "Cannot connect to cluster, skipping application deletion"
        return 0
    fi
    
    # Delete app namespaces
    for namespace in apps ingress-nginx cert-manager; do
        if kubectl get namespace "$namespace" >/dev/null 2>&1; then
            log_info "Deleting namespace: $namespace"
            kubectl delete namespace "$namespace" --wait=false || true
        fi
    done
}

# Delete cluster
delete_cluster() {
    log_info "Deleting KOPS cluster..."
    
    if ! cluster_exists; then
        log_warning "Cluster does not exist: $CLUSTER_NAME"
        return 0
    fi
    
    # Delete cluster (this will delete all AWS resources)
    kops delete cluster \
        --name="$CLUSTER_NAME" \
        --state="$KOPS_STATE_STORE" \
        --yes
    
    log_info "Waiting for resources to be deleted..."
    sleep 30
}

# Delete state store
delete_state_store_bucket() {
    if [[ "$DELETE_STATE_STORE" != "true" ]]; then
        log_info "Keeping S3 state store bucket (use --delete-state-store to remove)"
        return 0
    fi
    
    log_info "Deleting S3 state store bucket..."
    
    # Check if bucket exists
    if ! aws s3 ls "$KOPS_STATE_STORE" --profile "$AWS_PROFILE" >/dev/null 2>&1; then
        log_warning "S3 bucket does not exist: $KOPS_STATE_STORE"
        return 0
    fi
    
    # Empty and delete bucket
    aws s3 rm "$KOPS_STATE_STORE" \
        --recursive \
        --profile "$AWS_PROFILE"
    
    aws s3 rb "$KOPS_STATE_STORE" \
        --profile "$AWS_PROFILE"
}

# Delete local configuration
delete_local_config() {
    if [[ "$DELETE_LOCAL_CONFIG" != "true" ]]; then
        log_info "Keeping local configuration (use --delete-local-config to remove)"
        return 0
    fi
    
    log_info "Deleting local configuration..."
    
    # Delete SSH keys
    if [[ -f "$SSH_KEY_PATH" ]]; then
        log_info "Deleting SSH key: $SSH_KEY_PATH"
        rm -f "$SSH_KEY_PATH" "${SSH_KEY_PATH}.pub"
    fi
    
    # Remove kubeconfig context
    if kubectl config get-contexts "$CLUSTER_NAME" >/dev/null 2>&1; then
        log_info "Removing kubeconfig context: $CLUSTER_NAME"
        kubectl config delete-context "$CLUSTER_NAME" || true
        kubectl config delete-cluster "$CLUSTER_NAME" || true
        
        # Delete user entries
        kubectl config unset "users.${CLUSTER_NAME}" || true
        kubectl config unset "users.${CLUSTER_NAME}-basic-auth" || true
    fi
}

# Clean up DNS records
clean_dns_records() {
    log_info "Cleaning up DNS records..."
    
    local hosted_zone_id
    hosted_zone_id=$(aws route53 list-hosted-zones-by-name \
        --query "HostedZones[?Name=='${DNS_ZONE}.'].Id" \
        --output text \
        --profile "$AWS_PROFILE" | cut -d'/' -f3)
    
    if [[ -z "$hosted_zone_id" ]]; then
        log_warning "Could not find hosted zone for $DNS_ZONE"
        return 0
    fi
    
    # Delete cluster-related DNS records
    for record in "api.${CLUSTER_NAME}" "api.internal.${CLUSTER_NAME}" "kops-controller.internal.${CLUSTER_NAME}"; do
        local record_exists
        record_exists=$(aws route53 list-resource-record-sets \
            --hosted-zone-id "$hosted_zone_id" \
            --query "ResourceRecordSets[?Name=='${record}.'].Name" \
            --output text \
            --profile "$AWS_PROFILE" 2>/dev/null || echo "")
        
        if [[ -n "$record_exists" ]]; then
            log_info "Deleting DNS record: $record"
            # Get current record value
            local record_value
            record_value=$(aws route53 list-resource-record-sets \
                --hosted-zone-id "$hosted_zone_id" \
                --query "ResourceRecordSets[?Name=='${record}.'].ResourceRecords[0].Value" \
                --output text \
                --profile "$AWS_PROFILE")
            
            local change_batch=$(cat <<EOF
{
    "Changes": [{
        "Action": "DELETE",
        "ResourceRecordSet": {
            "Name": "${record}.",
            "Type": "A",
            "TTL": 300,
            "ResourceRecords": [{"Value": "${record_value}"}]
        }
    }]
}
EOF
)
            
            aws route53 change-resource-record-sets \
                --hosted-zone-id "$hosted_zone_id" \
                --change-batch "$change_batch" \
                --profile "$AWS_PROFILE" >/dev/null 2>&1 || true
        fi
    done
}

# Print summary
print_summary() {
    echo
    log_info "Teardown completed!"
    echo
    echo "Summary:"
    echo "========"
    echo "✓ Cluster deleted: $CLUSTER_NAME"
    if [[ "$DELETE_STATE_STORE" == "true" ]]; then
        echo "✓ S3 state store deleted: $KOPS_STATE_STORE"
    else
        echo "• S3 state store kept: $KOPS_STATE_STORE"
    fi
    if [[ "$DELETE_LOCAL_CONFIG" == "true" ]]; then
        echo "✓ Local configuration deleted"
    else
        echo "• Local configuration kept"
    fi
    echo
}

# Main execution
main() {
    log_info "Starting Kubernetes cluster teardown..."
    
    # Verify prerequisites
    if ! verify_prerequisites; then
        exit 1
    fi
    
    # Check if cluster exists
    if ! cluster_exists && [[ "$DELETE_STATE_STORE" != "true" ]] && [[ "$DELETE_LOCAL_CONFIG" != "true" ]]; then
        log_warning "Cluster does not exist and no cleanup options specified"
        exit 0
    fi
    
    # Confirm teardown
    confirm_teardown
    
    # Teardown steps
    delete_applications
    delete_cluster
    clean_dns_records
    delete_state_store_bucket
    delete_local_config
    
    print_summary
}

# Run main function
main "$@"