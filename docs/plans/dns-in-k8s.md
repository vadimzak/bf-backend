# Plan: Implement ExternalDNS for Automated K8S DNS Management

## Overview
Integrate ExternalDNS into your existing Kubernetes cluster to automate Route53 DNS record management based on Ingress resources.

## Current DNS Management Status

**Yes, DNS can be managed via Kubernetes**, and you already have partial DNS automation in place. Currently your setup uses:

1. **Manual DNS Management**: Scripts like `update-wildcard-dns.sh` that use AWS Route53 CLI to update DNS records
2. **cert-manager**: Already installed for SSL certificate management with Let's Encrypt
3. **Route53 Integration**: Your `k8s-common.sh` has `update_dns_record()` function that manages Route53 records

## Available K8S DNS Management Options

### Option 1: ExternalDNS (Recommended)
ExternalDNS is the standard K8S solution that automatically manages DNS records based on Ingress and Service annotations.

**Benefits**:
- Automatic DNS record creation/deletion when deploying apps
- Integrates with Route53, CloudFlare, and 50+ DNS providers
- Works with your existing cert-manager setup
- Eliminates manual DNS script execution

**How it works**:
- Watches Ingress resources for hostname annotations
- Automatically creates/updates Route53 records
- Cleans up DNS records when Ingress is deleted

### Option 2: Enhanced cert-manager DNS01 Challenges
Your current cert-manager setup likely uses HTTP01 challenges. DNS01 challenges via Route53 can provide:
- Wildcard certificate support
- Better integration with DNS management
- Automatic DNS record management for certificate validation

### Option 3: Kubernetes DNS Operators
Advanced operators like:
- **Crossplane** - Infrastructure as code via K8S resources
- **AWS Load Balancer Controller** - Integrates with Route53 for LoadBalancer services

## Implementation Steps

### 1. Create ExternalDNS Service Account & IAM Permissions
- Create IAM policy for Route53 access
- Set up service account with proper RBAC permissions
- Configure IAM role or access keys for ExternalDNS

### 2. Install ExternalDNS via Helm
- Add ExternalDNS Helm repository
- Deploy ExternalDNS configured for Route53 and your domain (vadimzak.com)
- Configure to watch `apps` namespace for Ingress resources

### 3. Update Ingress Resources
- Add ExternalDNS annotations to existing ingress files
- Configure automatic DNS record creation
- Test with sample-app and sample-6 applications

### 4. Create Management Scripts
- `scripts/k8s/install-external-dns.sh` - Install/configure ExternalDNS
- `scripts/k8s/verify-dns-automation.sh` - Verify DNS automation is working
- Update existing scripts to work with automated DNS

### 5. Documentation & Integration
- Update CLAUDE.md with new DNS automation workflow
- Document migration from manual to automated DNS
- Create troubleshooting guide for DNS issues

## Benefits
- **Eliminates manual DNS updates**: No more running `update-wildcard-dns.sh`
- **Automatic cleanup**: DNS records removed when apps are deleted
- **Faster deployments**: DNS updates happen automatically during app deployment
- **Reduced errors**: No manual DNS management steps to forget
- **Better GitOps**: DNS becomes part of your K8S manifests

## Estimated Timeline
- 2-3 hours for complete implementation and testing
- Minimal disruption to existing applications
- Can be implemented incrementally (one app at a time)

## Example ExternalDNS Configuration

### Helm Values
```yaml
# external-dns-values.yaml
provider: aws
aws:
  zoneType: public
  region: il-central-1
  preferCNAME: true
domainFilters:
  - vadimzak.com
sources:
  - ingress
txtOwnerId: k8s-cluster
```

### Ingress Annotations
```yaml
# Add to existing ingress resources
metadata:
  annotations:
    external-dns.alpha.kubernetes.io/hostname: sample.vadimzak.com
    external-dns.alpha.kubernetes.io/ttl: "300"
```

## Migration Strategy
1. Install ExternalDNS in dry-run mode first
2. Verify it detects existing Ingress resources correctly
3. Enable write mode to start managing DNS records
4. Gradually phase out manual DNS update scripts
5. Monitor DNS propagation and troubleshoot any issues