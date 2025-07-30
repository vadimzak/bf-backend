# Kubernetes Elastic IP Troubleshooting Guide

This guide helps resolve common issues with Elastic IP allocation when setting up HTTPS on port 443.

## Common Error: "Secondary IP exists but has no public IP associated"

This error occurs when the secondary IP setup succeeds but AWS cannot allocate an Elastic IP due to account limits.

### Quick Resolution Steps

1. **Check your current Elastic IP usage**:
   ```bash
   ./scripts/k8s/cleanup-secondary-ip.sh --dry-run
   ```

2. **Release unused Elastic IPs**:
   ```bash
   ./scripts/k8s/cleanup-secondary-ip.sh
   ```

3. **If still at limit, request an increase**:
   ```bash
   aws service-quotas request-service-quota-increase \
     --service-code ec2 --quota-code L-0263D0A3 \
     --desired-value 10 --region il-central-1 --profile bf
   ```

4. **Or use the cluster without secondary IP** (HTTPS on port 30443):
   ```bash
   ./scripts/k8s/teardown-cluster.sh
   ./scripts/k8s/bootstrap-cluster.sh --no-secondary-ip
   ```

## Understanding AWS Elastic IP Limits

- Default limit: 5 Elastic IPs per region
- Each secondary IP for HTTPS requires 1 Elastic IP
- The limit applies to all EC2 resources in the region

## Improved Error Handling (July 2025)

The scripts now include:

1. **Pre-allocation checks**: Verifies available Elastic IPs before attempting allocation
2. **Automatic reuse**: Finds and reuses unassociated Elastic IPs
3. **Clear error messages**: Provides specific steps to resolve issues
4. **Cleanup integration**: `teardown-cluster.sh` now cleans up secondary IP resources

## New Cleanup Script

The `cleanup-secondary-ip.sh` script helps manage Elastic IP resources:

```bash
# Check what would be cleaned up
./scripts/k8s/cleanup-secondary-ip.sh --dry-run

# Clean up with confirmation prompts
./scripts/k8s/cleanup-secondary-ip.sh

# Force cleanup without prompts
./scripts/k8s/cleanup-secondary-ip.sh --force
```

## Cost Considerations

- Secondary IP with Elastic IP: ~$3.60/month
- Without secondary IP: No additional cost, but HTTPS only on port 30443

## Diagnostic Commands

```bash
# Check all Elastic IPs in your account
aws ec2 describe-addresses --profile bf --region il-central-1 \
  --query 'Addresses[].[PublicIp,AssociationId,InstanceId]' \
  --output table

# Check your current limit
aws service-quotas get-service-quota \
  --service-code ec2 --quota-code L-0263D0A3 \
  --region il-central-1 --profile bf

# Run full diagnostics
./scripts/k8s/diagnose-secondary-ip.sh
```

## Bootstrap Options

```bash
# Default: WITH secondary IP (HTTPS on port 443)
./scripts/k8s/bootstrap-cluster.sh

# WITHOUT secondary IP (HTTPS on port 30443)
./scripts/k8s/bootstrap-cluster.sh --no-secondary-ip

# Quick start with all features
./scripts/k8s/quick-start-full.sh

# Quick start without secondary IP
./scripts/k8s/quick-start-full.sh --no-secondary-ip
```