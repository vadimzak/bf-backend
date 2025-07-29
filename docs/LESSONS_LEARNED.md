# Kubernetes Migration: Lessons Learned

This document captures key lessons learned during the migration from Docker Compose to Kubernetes using KOPS.

## Key Mistakes and Solutions

### 1. Region Selection
**Mistake**: Initially tried to create cluster in us-east-1 region.
**Issue**: Resources and configuration were not optimal for our use case.
**Solution**: Use il-central-1 region as specified in requirements.
**Learning**: Always verify region requirements before starting infrastructure deployment.

### 2. KOPS Node Requirements
**Mistake**: Attempted to create a cluster without any node instance groups.
**Issue**: KOPS requires at least one node instance group, even if set to 0 instances.
**Solution**: Create a minimal node instance group with minSize=0, maxSize=0.
```yaml
spec:
  machineType: t3.small
  maxSize: 0
  minSize: 0
  role: Node
```

### 3. Single-Node Configuration
**Mistake**: Initially used deprecated flags (--master-size, --master-count).
**Issue**: KOPS now uses --control-plane-size and --control-plane-count.
**Solution**: Use updated flags and configure control plane to accept workloads:
- Remove taints from control plane
- Set `masterKubelet.registerSchedulable: true` in cluster spec
- Use `kubectl taint nodes --all node-role.kubernetes.io/control-plane:NoSchedule-`

### 4. DNS Configuration
**Mistake**: Expected DNS to update automatically immediately.
**Issue**: DNS controller needs time to start and update records.
**Solution**: 
- Manually update DNS records if needed for faster deployment
- Use placeholder IP (203.0.113.123) detection to know when to update
- Wait for DNS propagation (5-15 minutes)

### 5. Security Group Rules
**Mistake**: Forgot to add rules for NodePort services.
**Issue**: NGINX Ingress controller uses NodePorts 30080/30443 by default.
**Solution**: Add security group rules:
```bash
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 30080 \
  --cidr 0.0.0.0/0
```

### 6. Tool Installation
**Mistake**: Assumed sudo would work in non-interactive scripts.
**Issue**: Scripts failed when trying to install tools to /usr/local/bin.
**Solution**: 
- Check if directory is writable first
- Provide clear instructions for manual sudo if needed
- Use temp directory for downloads

### 7. Cluster Validation Timing
**Mistake**: Expected cluster to be ready immediately after creation.
**Issue**: Cluster takes 5-10 minutes to fully initialize.
**Solution**: 
- Use `kubectl wait` commands with appropriate timeouts
- Check specific conditions rather than general validation
- Provide clear progress indicators

### 8. etcd Initialization on New Clusters
**Mistake**: etcd-manager failing with "etcd has 0 members registered" on new clusters.
**Issue**: etcd-manager expects restore-backup command for initialization.
**Solution**:
- Use stable Kubernetes version (1.28.5)
- Wait for kops validate cluster to pass before checking API
- Allow sufficient time for etcd to initialize (use 20s intervals)
- Check instance status if initialization takes too long

### 9. DNS Resolution and kubectl Access
**Mistake**: kubectl fails with "no such host" even after DNS is updated.
**Issue**: Local DNS caching and TLS certificate validation.
**Solution**:
- Created fix-dns.sh script to handle DNS issues
- Use direct IP with --insecure-skip-tls-verify temporarily
- Provide clear instructions for switching between IP and DNS access
- Document in bootstrap script output

### 10. Ingress Controller on Single Node
**Mistake**: Ingress controller pod pending due to port conflicts with hostNetwork.
**Issue**: Single node can't bind to host ports 80/443 if already in use.
**Solution**:
- Use Deployment instead of DaemonSet
- Disable hostNetwork for single-node clusters
- Use NodePort service type (30080/30443)
- Updated bootstrap script to use correct configuration

### 11. Cert-Manager Webhook Timing
**Mistake**: ClusterIssuer creation fails if applied too quickly.
**Issue**: Cert-manager webhook needs time to start.
**Solution**:
- Add 30-second wait after cert-manager installation
- Create Route53 secret separately before ClusterIssuer
- Include AWS credentials properly in ClusterIssuer spec

## Best Practices Discovered

### 1. Script Organization
- Separate common functions into lib/k8s-common.sh
- Use consistent error handling and logging
- Make scripts idempotent where possible
- Provide dry-run options for safety

### 2. Resource Management
- Use single node for development/staging to save costs
- t3.small is minimum viable size for K8s control plane
- Enable spot instances for workers when scaling up
- Use on-demand for control plane for stability

### 3. Application Configuration
- Keep deploy.config files for app-specific settings
- Generate K8s manifests programmatically for consistency
- Use Kustomize for managing manifests
- Tag Docker images with timestamps for versioning

### 4. Security Considerations
- Use separate AWS profile for isolation
- Implement least-privilege IAM policies
- Enable encryption for etcd volumes
- Use cert-manager for automatic SSL certificates

### 5. Deployment Workflow
1. Always verify prerequisites first
2. Create state store before cluster
3. Wait for cluster to be fully ready before installing components
4. Test connectivity before deploying applications
5. Document all manual steps for automation

## Cost Optimizations

### Original Estimate vs Reality
- **Estimated**: $18-22/month
- **Actual**: ~$20-25/month (including EBS volumes and data transfer)
- **Comparison**: 5-6x more expensive than Docker Compose setup

### Cost Breakdown
- EC2 t3.small (on-demand): ~$15/month
- EBS Volumes (2x20GB): ~$3-4/month
- Data Transfer: ~$2-3/month
- Route53: $0.50/month

### Optimization Opportunities
1. Use spot instances for development (70% savings)
2. Schedule cluster shutdown during off-hours
3. Use smaller EBS volumes if possible
4. Consider k3s or microk8s for lighter weight

## Migration Timeline

### Planned vs Actual
- **Planned**: 2-3 days
- **Actual**: 1 day for basic setup
- **Note**: Additional time needed for application migration and testing

### Time Breakdown
1. Tool installation and setup: 30 minutes
2. Cluster creation and configuration: 1-2 hours
3. Component installation: 30 minutes
4. Application configuration: 1-2 hours per app
5. Testing and validation: 2-3 hours

## Recommendations

### For Future Migrations
1. Start with scripts, not manual commands
2. Test in a separate AWS account first
3. Document every decision and configuration
4. Use infrastructure as code from the beginning
5. Plan for DNS propagation delays

### For Production Use
1. Add monitoring and alerting (Prometheus/Grafana)
2. Implement backup strategies for etcd
3. Set up multi-node cluster for HA
4. Use separate clusters for staging/production
5. Implement GitOps for deployments

### Alternative Approaches
1. **EKS**: Managed Kubernetes, higher cost but less maintenance
2. **k3s on EC2**: Lighter weight, suitable for single node
3. **Docker Swarm**: Simpler than K8s, good for small deployments
4. **Keep Docker Compose**: Honestly the best option for this use case

## Conclusion

While Kubernetes provides powerful orchestration capabilities, for a simple multi-app deployment with cost constraints, the original Docker Compose setup is more appropriate. The 5-6x cost increase and added complexity are hard to justify unless you need:

- Multi-node scaling
- Advanced deployment strategies
- Complex service mesh
- Multi-tenancy
- Regulatory compliance requirements

The scripts created make it easy to spin up a K8s cluster when needed, but for day-to-day operations, Docker Compose remains the pragmatic choice.