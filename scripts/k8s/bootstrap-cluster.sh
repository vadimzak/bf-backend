#!/bin/bash
set -euo pipefail

# Bootstrap Kubernetes cluster using KOPS
# This script creates a single-node K8s cluster on AWS

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/k8s-common.sh"

# Set error handling
set_error_trap

# Script options
DRY_RUN=false
SKIP_PREREQUISITES=false
SKIP_DNS_CHECK=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-prerequisites)
            SKIP_PREREQUISITES=true
            shift
            ;;
        --skip-dns-check)
            SKIP_DNS_CHECK=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run            Show what would be done without making changes"
            echo "  --skip-prerequisites Skip prerequisites check"
            echo "  --skip-dns-check     Skip DNS propagation check"
            echo "  --help               Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run command or show what would be run
run_cmd() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] $*"
    else
        "$@"
    fi
}

# Check etcd health
check_etcd_health() {
    local master_ip
    master_ip=$(get_master_ip 2>/dev/null || echo "")
    
    if [[ -z "$master_ip" ]]; then
        return 1
    fi
    
    # Try to SSH and check etcd-manager logs
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "$SSH_KEY_PATH" "ubuntu@$master_ip" \
        "sudo journalctl -u etcd-manager-main -n 50 --no-pager" 2>/dev/null | grep -q "etcd has 0 members registered"; then
        log_warning "etcd initialization issue detected"
        return 1
    fi
    
    return 0
}

# Create S3 bucket for KOPS state
create_state_store() {
    log_info "Creating S3 bucket for KOPS state store..."
    
    # Check if bucket exists
    if aws s3 ls "$KOPS_STATE_STORE" --profile "$AWS_PROFILE" >/dev/null 2>&1; then
        log_info "S3 bucket already exists: $KOPS_STATE_STORE"
    else
        run_cmd aws s3 mb "$KOPS_STATE_STORE" --profile "$AWS_PROFILE" --region "$AWS_REGION"
        run_cmd aws s3api put-bucket-versioning \
            --bucket "${KOPS_STATE_STORE#s3://}" \
            --versioning-configuration Status=Enabled \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION"
    fi
}

# Generate SSH key for KOPS
generate_ssh_key() {
    if [[ -f "$SSH_KEY_PATH" ]]; then
        log_info "SSH key already exists: $SSH_KEY_PATH"
    else
        log_info "Generating SSH key for KOPS..."
        run_cmd ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N ""
    fi
}

# Create KOPS cluster
create_cluster() {
    log_info "Creating KOPS cluster configuration..."
    
    # Check if cluster already exists
    if cluster_exists; then
        log_warning "Cluster already exists: $CLUSTER_NAME"
        return 0
    fi
    
    # Create cluster with single master
    run_cmd kops create cluster \
        --name="$CLUSTER_NAME" \
        --state="$KOPS_STATE_STORE" \
        --zones="${AWS_REGION}a" \
        --control-plane-size="$MASTER_SIZE" \
        --control-plane-count=1 \
        --node-size="$NODE_SIZE" \
        --node-count="$NODE_COUNT" \
        --dns-zone="$DNS_ZONE" \
        --dns=public \
        --ssh-public-key="${SSH_KEY_PATH}.pub" \
        --networking=calico \
        --topology=public \
        --bastion=false \
        --api-loadbalancer-type="" \
        --kubernetes-version="$K8S_VERSION"
    
    # Delete the default nodes instance group for single-node setup
    log_info "Removing default nodes instance group..."
    run_cmd kops delete ig "nodes-${AWS_REGION}a" --name="$CLUSTER_NAME" --yes
    
    # Configure master to accept workloads
    log_info "Configuring master node to accept workloads..."
    
    # Create temporary instance group configuration
    local ig_config="/tmp/control-plane-ig.yaml"
    cat > "$ig_config" <<EOF
apiVersion: kops.k8s.io/v1alpha2
kind: InstanceGroup
metadata:
  labels:
    kops.k8s.io/cluster: ${CLUSTER_NAME}
  name: control-plane-${AWS_REGION}a
spec:
  image: 099720109477/ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-20250610
  machineType: ${MASTER_SIZE}
  maxSize: 1
  minSize: 1
  role: Master
  subnets:
  - ${AWS_REGION}a
  taints: []
EOF
    
    run_cmd kops replace -f "$ig_config"
    rm -f "$ig_config"
    
    # Update cluster spec to allow scheduling on master and configure API server port
    local cluster_spec="/tmp/cluster-spec.yaml"
    kops get cluster "$CLUSTER_NAME" -o yaml > "$cluster_spec"
    
    # Add masterKubelet configuration
    if ! grep -q "masterKubelet:" "$cluster_spec"; then
        # Use a more robust method to add the configuration
        local temp_spec="/tmp/cluster-spec-temp.yaml"
        awk '/^spec:/ {print; print "  masterKubelet:"; print "    registerSchedulable: true"; next} {print}' "$cluster_spec" > "$temp_spec"
        mv "$temp_spec" "$cluster_spec"
    fi
    
    run_cmd kops replace -f "$cluster_spec"
    rm -f "$cluster_spec"
    
    # Create minimal nodes instance group (required by KOPS)
    log_info "Creating minimal nodes instance group..."
    local nodes_ig="/tmp/nodes-ig.yaml"
    cat > "$nodes_ig" <<EOF
apiVersion: kops.k8s.io/v1alpha2
kind: InstanceGroup
metadata:
  labels:
    kops.k8s.io/cluster: ${CLUSTER_NAME}
  name: nodes-${AWS_REGION}a
spec:
  image: 099720109477/ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-20250610
  machineType: ${NODE_SIZE}
  maxSize: 0
  minSize: 0
  role: Node
  subnets:
  - ${AWS_REGION}a
EOF
    
    run_cmd kops create -f "$nodes_ig"
    rm -f "$nodes_ig"
}

# Deploy cluster
deploy_cluster() {
    log_info "Deploying Kubernetes cluster..."
    
    run_cmd kops update cluster --name="$CLUSTER_NAME" --yes --admin
    
    log_info "Cluster deployment initiated. Waiting for cluster to be ready..."
    
    # Wait for cluster validation to pass
    log_info "Waiting for cluster validation..."
    local validation_attempts=0
    local max_validation_attempts=30
    
    while [[ $validation_attempts -lt $max_validation_attempts ]]; do
        if kops validate cluster --wait=10s >/dev/null 2>&1; then
            log_info "Cluster validation passed"
            break
        fi
        
        validation_attempts=$((validation_attempts + 1))
        if [[ $((validation_attempts % 5)) -eq 0 ]]; then
            log_info "Still waiting for cluster validation... ($validation_attempts/$max_validation_attempts)"
        fi
        sleep 20
    done
    
    # Export kubeconfig
    export KUBECONFIG="$HOME/.kube/config"
    kops export kubecfg --admin >/dev/null 2>&1 || true
    
    # Wait for API to be accessible
    log_info "Waiting for API server to be ready..."
    local attempts=0
    local max_attempts=60
    
    while [[ $attempts -lt $max_attempts ]]; do
        if kubectl get nodes >/dev/null 2>&1; then
            log_info "API server is accessible"
            break
        fi
        
        # Try with IP directly if DNS fails
        if [[ $attempts -eq 10 ]]; then
            log_warning "DNS resolution might be cached, trying with IP directly"
            local master_ip
            master_ip=$(get_master_ip)
            if [[ -n "$master_ip" ]]; then
                kubectl config set-cluster "$CLUSTER_NAME" --server="https://$master_ip" >/dev/null 2>&1
                sleep 5
                if kubectl get nodes >/dev/null 2>&1; then
                    log_info "Connected using IP directly"
                    # Restore DNS URL for future use
                    kubectl config set-cluster "$CLUSTER_NAME" --server="https://api.$CLUSTER_NAME" >/dev/null 2>&1
                    break
                fi
                # Restore DNS URL if IP didn't work
                kubectl config set-cluster "$CLUSTER_NAME" --server="https://api.$CLUSTER_NAME" >/dev/null 2>&1
            fi
        fi
        
        attempts=$((attempts + 1))
        if [[ $((attempts % 6)) -eq 0 ]]; then
            log_info "Still waiting for API server... ($attempts/60)"
            # Check etcd status if we're having issues
            if [[ $attempts -ge 30 ]]; then
                log_warning "Checking instance status..."
                local instance_id
                instance_id=$(aws ec2 describe-instances \
                    --filters "Name=tag:Name,Values=${CLUSTER_NAME}-master-${AWS_REGION}a" \
                              "Name=instance-state-name,Values=running" \
                    --query 'Reservations[0].Instances[0].InstanceId' \
                    --output text \
                    --profile "$AWS_PROFILE" \
                    --region "$AWS_REGION" 2>/dev/null || echo "")
                
                if [[ -n "$instance_id" ]] && [[ "$instance_id" != "None" ]]; then
                    log_info "Master instance is running: $instance_id"
                fi
            fi
        fi
        sleep 10
    done
    
    if [[ $attempts -eq $max_attempts ]]; then
        log_error "Cluster API not accessible after 10 minutes"
        return 1
    fi
    
    # Get master IP
    local master_ip
    master_ip=$(get_master_ip)
    if [[ -z "$master_ip" ]]; then
        log_error "Could not get master node IP"
        return 1
    fi
    
    log_info "Master node IP: $master_ip"
    
    # Update DNS if needed
    if [[ "$SKIP_DNS_CHECK" != "true" ]]; then
        log_info "Updating DNS records..."
        run_cmd update_dns_record "api.${CLUSTER_NAME}" "$master_ip"
        
        # Wait for DNS propagation
        log_info "Waiting for DNS propagation..."
        sleep 30
    fi
    
    # Wait for node to be ready
    log_info "Waiting for node to be ready..."
    if ! run_cmd kubectl wait --for=condition=Ready node --all --timeout=10m; then
        log_error "Node did not become ready in time"
        return 1
    fi
    
    # Remove taint from control plane to allow workloads
    log_info "Removing control plane taint..."
    run_cmd kubectl taint nodes --all node-role.kubernetes.io/control-plane:NoSchedule- || true
    
    # Configure kubectl to handle DNS issues
    log_info "Configuring kubectl for DNS resilience..."
    if [[ -n "$master_ip" ]]; then
        # Create a backup of the original config
        cp "$HOME/.kube/config" "$HOME/.kube/config.backup" 2>/dev/null || true
        
        # Add note about DNS
        log_warning "If you experience DNS resolution issues, you can temporarily use:"
        log_warning "  kubectl config set-cluster $CLUSTER_NAME --server=https://$master_ip --insecure-skip-tls-verify=true"
        log_warning "To restore DNS-based access:"
        log_warning "  kubectl config set-cluster $CLUSTER_NAME --server=https://api.$CLUSTER_NAME"
    fi
}

# Configure security groups
configure_security_groups() {
    log_info "Configuring security groups..."
    
    # Wait a bit for security groups to be created
    sleep 10
    
    # Add rules for HTTP/HTTPS traffic
    run_cmd add_security_group_rule 80 tcp
    run_cmd add_security_group_rule 443 tcp
    run_cmd add_security_group_rule 30080 tcp  # NodePort HTTP
    run_cmd add_security_group_rule 30443 tcp  # NodePort HTTPS
}

# Install core components
install_core_components() {
    log_info "Installing core Kubernetes components..."
    
    # Create namespaces
    log_info "Creating namespaces..."
    run_cmd kubectl create namespace apps || true
    run_cmd kubectl create namespace ingress-nginx || true
    run_cmd kubectl create namespace cert-manager || true
    
    # Install NGINX Ingress Controller
    log_info "Installing NGINX Ingress Controller..."
    run_cmd helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx || true
    run_cmd helm repo update
    
    # Use Deployment instead of DaemonSet to avoid port conflicts on single node
    run_cmd helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
        --namespace ingress-nginx \
        --set controller.service.type=NodePort \
        --set controller.service.nodePorts.http=30080 \
        --set controller.service.nodePorts.https=30443 \
        --set controller.kind=Deployment \
        --set controller.hostNetwork=false \
        --wait --timeout=5m
    
    # Install cert-manager
    log_info "Installing cert-manager..."
    run_cmd kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
    
    # Wait for cert-manager to be ready
    log_info "Waiting for cert-manager to be ready..."
    run_cmd kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/instance=cert-manager \
        -n cert-manager \
        --timeout=5m || true
    
    # Wait for cert-manager webhook to be ready
    log_info "Waiting for cert-manager webhook to be ready..."
    sleep 30  # Give webhook time to start
    
    # Create ClusterIssuer for Let's Encrypt
    log_info "Creating Let's Encrypt ClusterIssuer..."
    local cluster_issuer="/tmp/letsencrypt-issuer.yaml"
    
    # Get AWS credentials
    local access_key_id
    access_key_id=$(aws configure get aws_access_key_id --profile "$AWS_PROFILE")
    
    # Create Route53 secret first
    kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: route53-secret
  namespace: cert-manager
type: Opaque
stringData:
  secret-access-key: $(aws configure get aws_secret_access_key --profile "$AWS_PROFILE")
EOF
    
    cat > "$cluster_issuer" <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@${DNS_ZONE}
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - dns01:
        route53:
          region: ${AWS_REGION}
          hostedZoneID: $(aws route53 list-hosted-zones-by-name \
            --query "HostedZones[?Name=='${DNS_ZONE}.'].Id" \
            --output text \
            --profile "$AWS_PROFILE" | cut -d'/' -f3)
          accessKeyID: $access_key_id
          secretAccessKeySecretRef:
            name: route53-secret
            key: secret-access-key
EOF
    
    run_cmd kubectl apply -f "$cluster_issuer"
    rm -f "$cluster_issuer"
}

# Print cluster information
print_cluster_info() {
    echo
    log_info "Cluster bootstrapped successfully!"
    echo
    echo "Cluster Information:"
    echo "==================="
    echo "Cluster Name: $CLUSTER_NAME"
    echo "State Store: $KOPS_STATE_STORE"
    echo "Region: $AWS_REGION"
    echo "Master IP: $(get_master_ip)"
    echo
    echo "Access cluster with:"
    echo "  kubectl get nodes"
    echo "  kubectl get pods --all-namespaces"
    echo
    echo "SSH to master node:"
    echo "  ssh -i $SSH_KEY_PATH ubuntu@$(get_master_ip)"
    echo
    echo "Next steps:"
    echo "1. Configure applications: ./scripts/k8s/configure-apps.sh"
    echo "2. Deploy applications to Kubernetes"
    echo "3. (Optional) Enable standard ports: ./scripts/k8s/setup-haproxy.sh"
    echo
}

# Main execution
main() {
    log_info "Starting Kubernetes cluster bootstrap..."
    
    # Check prerequisites
    if [[ "$SKIP_PREREQUISITES" != "true" ]]; then
        log_info "Verifying prerequisites..."
        if ! verify_prerequisites; then
            exit 1
        fi
    fi
    
    # Check if cluster already exists
    local cluster_status
    cluster_status=$(get_cluster_status)
    if [[ "$cluster_status" == "running" ]]; then
        log_warning "Cluster is already running"
        print_cluster_info
        exit 0
    fi
    
    # Bootstrap steps
    create_state_store
    generate_ssh_key
    create_cluster
    
    if [[ "$DRY_RUN" != "true" ]]; then
        deploy_cluster
        configure_security_groups
        install_core_components
        print_cluster_info
    else
        log_info "[DRY RUN] Cluster configuration created. Run without --dry-run to deploy."
    fi
}

# Run main function
main "$@"