#!/bin/bash
set -euo pipefail

# Cleanup script for secondary IP resources
# Use this to clean up failed secondary IP setup attempts

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/k8s-common.sh"

# Set error handling
set_error_trap

# Script options
FORCE=false
DRY_RUN=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --force      Remove resources without confirmation"
            echo "  --dry-run    Show what would be removed without making changes"
            echo "  --help       Show this help message"
            echo ""
            echo "This script cleans up secondary IP resources that might be"
            echo "left over from failed setup attempts."
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
        echo "[DRY RUN] $*" >&2
        return 0
    else
        "$@"
    fi
}

# Main cleanup function
main() {
    log_info "Starting secondary IP resource cleanup..."
    
    # Get master node information
    local master_ip
    master_ip=$(get_master_ip)
    
    if [[ -z "$master_ip" ]]; then
        log_warning "No master node found. Checking for orphaned resources..."
    else
        log_info "Found master node: $master_ip"
        
        # Get instance ID
        local instance_id
        instance_id=$(aws ec2 describe-instances \
            --filters "Name=network-interface.association.public-ip,Values=$master_ip" \
                      "Name=instance-state-name,Values=running" \
            --query 'Reservations[0].Instances[0].InstanceId' \
            --output text \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION" 2>/dev/null || echo "None")
        
        if [[ -n "$instance_id" ]] && [[ "$instance_id" != "None" ]]; then
            # Get ENI
            local eni_id
            eni_id=$(aws ec2 describe-instances \
                --instance-ids "$instance_id" \
                --query 'Reservations[0].Instances[0].NetworkInterfaces[0].NetworkInterfaceId' \
                --output text \
                --profile "$AWS_PROFILE" \
                --region "$AWS_REGION" 2>/dev/null || echo "None")
            
            if [[ -n "$eni_id" ]] && [[ "$eni_id" != "None" ]]; then
                # Check for secondary IPs
                local secondary_ips
                secondary_ips=$(aws ec2 describe-network-interfaces \
                    --network-interface-ids "$eni_id" \
                    --query 'NetworkInterfaces[0].PrivateIpAddresses[?Primary==`false`].PrivateIpAddress' \
                    --output text \
                    --profile "$AWS_PROFILE" \
                    --region "$AWS_REGION" 2>/dev/null || echo "")
                
                if [[ -n "$secondary_ips" ]] && [[ "$secondary_ips" != "None" ]]; then
                    log_info "Found secondary IPs on current master: $secondary_ips"
                    
                    if [[ "$FORCE" != "true" ]] && [[ "$DRY_RUN" != "true" ]]; then
                        read -p "Remove secondary IPs from current master? (y/N) " -n 1 -r
                        echo
                        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                            log_info "Skipping secondary IP removal"
                        else
                            FORCE=true
                        fi
                    fi
                    
                    if [[ "$FORCE" == "true" ]]; then
                        for ip in $secondary_ips; do
                            log_info "Removing secondary IP: $ip"
                            run_cmd aws ec2 unassign-private-ip-addresses \
                                --network-interface-id "$eni_id" \
                                --private-ip-addresses "$ip" \
                                --profile "$AWS_PROFILE" \
                                --region "$AWS_REGION"
                        done
                    fi
                fi
                
                # Clean up on the instance
                if [[ -n "$master_ip" ]]; then
                    log_info "Cleaning up instance configuration..."
                    
                    if [[ "$DRY_RUN" == "true" ]]; then
                        echo "[DRY RUN] Would clean up instance configuration on $master_ip"
                    else
                        ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "ubuntu@$master_ip" << 'EOF' || true
                            # Remove secondary IP configuration
                            sudo rm -f /etc/netplan/99-secondary-ip.yaml
                            
                            # Remove iptables rules for secondary IP
                            sudo iptables -t nat -L PREROUTING -n --line-numbers | \
                                grep "REDIRECT.*tcp dpt:443 redir ports 8443" | \
                                awk '{print $1}' | sort -nr | \
                                while read line; do
                                    sudo iptables -t nat -D PREROUTING $line
                                done
                            
                            # Save iptables rules
                            if command -v netfilter-persistent >/dev/null 2>&1; then
                                sudo netfilter-persistent save
                            fi
                            
                            # Remove kube-api-forward service if it exists
                            if systemctl is-enabled kube-api-forward >/dev/null 2>&1; then
                                sudo systemctl stop kube-api-forward
                                sudo systemctl disable kube-api-forward
                                sudo rm -f /etc/systemd/system/kube-api-forward.service
                                sudo systemctl daemon-reload
                            fi
                            
                            # Apply netplan
                            sudo netplan apply
                            
                            echo "Instance cleanup completed"
EOF
                    fi
                fi
            fi
        fi
    fi
    
    # Check for unassociated Elastic IPs
    log_info "Checking for unassociated Elastic IPs..."
    local unused_eips
    unused_eips=$(aws ec2 describe-addresses \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --query 'Addresses[?AssociationId==`null`].[AllocationId,PublicIp]' \
        --output text 2>/dev/null)
    
    if [[ -n "$unused_eips" ]]; then
        echo "Found unassociated Elastic IPs:"
        echo "$unused_eips" | while read alloc_id public_ip; do
            echo "  - $public_ip (AllocationId: $alloc_id)"
        done
        
        if [[ "$FORCE" != "true" ]] && [[ "$DRY_RUN" != "true" ]]; then
            read -p "Release these Elastic IPs? (y/N) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Keeping Elastic IPs"
            else
                FORCE=true
            fi
        fi
        
        if [[ "$FORCE" == "true" ]]; then
            echo "$unused_eips" | while read alloc_id public_ip; do
                if [[ -n "$alloc_id" ]]; then
                    log_info "Releasing Elastic IP: $public_ip"
                    run_cmd aws ec2 release-address \
                        --allocation-id "$alloc_id" \
                        --profile "$AWS_PROFILE" \
                        --region "$AWS_REGION"
                fi
            done
        fi
    else
        log_info "No unassociated Elastic IPs found"
    fi
    
    # Check Elastic IP limits
    log_info "Checking Elastic IP allocation limits..."
    local eip_count
    eip_count=$(aws ec2 describe-addresses \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --query 'length(Addresses)' \
        --output text 2>/dev/null || echo "0")
    
    log_info "Current Elastic IPs in use: $eip_count"
    
    # Get the limit (this requires proper IAM permissions)
    local eip_limit
    eip_limit=$(aws service-quotas get-service-quota \
        --service-code ec2 \
        --quota-code L-0263D0A3 \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --query 'Quota.Value' \
        --output text 2>/dev/null || echo "5")
    
    log_info "Elastic IP limit: $eip_limit"
    
    if [[ $eip_count -ge ${eip_limit%.*} ]]; then
        log_warning "You are at or near your Elastic IP limit!"
        log_warning "Consider releasing unused IPs or requesting a limit increase"
    fi
    
    echo
    log_info "Cleanup complete!"
    echo
    echo "Summary:"
    echo "========"
    echo "- Elastic IPs in use: $eip_count / $eip_limit"
    if [[ -n "$secondary_ips" ]]; then
        echo "- Secondary IPs found: $secondary_ips"
    fi
    echo
    echo "Next steps:"
    echo "==========="
    echo "1. If you need to increase Elastic IP limits:"
    echo "   aws service-quotas request-service-quota-increase \\"
    echo "     --service-code ec2 --quota-code L-0263D0A3 \\"
    echo "     --desired-value 10 --region $AWS_REGION --profile $AWS_PROFILE"
    echo
    echo "2. To retry secondary IP setup:"
    echo "   ./scripts/k8s/setup-secondary-ip.sh"
    echo
    echo "3. To diagnose issues:"
    echo "   ./scripts/k8s/diagnose-secondary-ip.sh"
}

# Run main function
main "$@"