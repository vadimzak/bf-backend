# Grafana Authentication Troubleshooting Guide

## Issue Summary

**Problem**: Grafana dashboards appear empty despite metrics being collected by Prometheus.

**Root Cause**: Grafana authentication misconfiguration preventing dashboard access. The Helm chart values specified anonymous authentication should be enabled, but these weren't properly converted to Grafana environment variables.

## Symptoms

1. Grafana login page appears instead of direct dashboard access
2. Login attempts fail with "Invalid username or password" 
3. Dashboards appear empty or inaccessible
4. Prometheus metrics are being collected correctly (visible at http://localhost:9090)

## Technical Details

### Expected Configuration
The monitoring stack should be configured with:
```yaml
grafana:
  auth:
    anonymous:
      enabled: true
      org_role: Admin
    disable_login_form: true
```

### Missing Environment Variables
The issue occurs when Helm values don't properly translate to Grafana environment variables:
- `GF_AUTH_ANONYMOUS_ENABLED=true`
- `GF_AUTH_ANONYMOUS_ORG_ROLE=Admin` 
- `GF_AUTH_DISABLE_LOGIN_FORM=true`

### Verification Commands
```bash
# Check if metrics are being collected
kubectl exec -n monitoring deployment/kube-prometheus-stack-grafana -- env | grep -E "GF_AUTH|ANONYMOUS|LOGIN"

# Should show:
# GF_AUTH_ANONYMOUS_ENABLED=true
# GF_AUTH_ANONYMOUS_ORG_ROLE=Admin
# GF_AUTH_DISABLE_LOGIN_FORM=true
```

## Solution

### Immediate Fix
```bash
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack -n monitoring \
  --set grafana.env.GF_AUTH_ANONYMOUS_ENABLED=true \
  --set grafana.env.GF_AUTH_ANONYMOUS_ORG_ROLE=Admin \
  --set grafana.env.GF_AUTH_DISABLE_LOGIN_FORM=true \
  --reuse-values
```

### Permanent Fix
Update the monitoring installation to include proper environment variables from the start.

## Validation

After applying the fix:

1. **Access Test**: Navigate to http://localhost:3000 (with port forwarding active)
2. **Expected Result**: Direct access to Grafana dashboards without login prompt
3. **Dashboard Verification**: Should see 20+ pre-configured Kubernetes dashboards
4. **Data Verification**: Dashboards should display real-time cluster metrics

## Prevention

1. **Installation Scripts**: Update monitoring installation scripts to include proper auth configuration
2. **Documentation**: Ensure bootstrap procedures include this configuration
3. **Validation**: Add post-installation checks to verify anonymous auth is working

## Related Files

- `scripts/k8s/install-monitoring.sh` - Primary installation script (needs update)
- `scripts/k8s/quick-start-full.sh` - Full bootstrap script (needs update)
- `CLAUDE.md` - Main documentation (needs monitoring section update)

## Common Pitfalls

1. **Helm Values vs Environment Variables**: Grafana Helm chart doesn't always properly convert nested auth values to environment variables
2. **Pod Restart Required**: Environment variable changes require pod restart to take effect
3. **Port Forwarding**: Authentication fixes require restarting port forwarding to new pod

## Historical Context

- **Date Identified**: July 31, 2025
- **Affected Versions**: kube-prometheus-stack Helm chart (multiple versions)
- **Impact**: Prevents monitoring dashboard access in fresh installations
- **Frequency**: Likely affects all new monitoring stack deployments

## Future Improvements

1. **Automated Validation**: Add post-installation checks to monitoring scripts
2. **Alternative Auth Methods**: Consider other authentication approaches for production
3. **Documentation Updates**: Keep troubleshooting guides updated with new discoveries

## Script Updates Made (July 31, 2025)

1. **install-monitoring.sh**: Added explicit environment variable configuration and post-installation validation
2. **quick-start-full.sh**: Added optional monitoring installation (enabled by default)
3. **CLAUDE.md**: Updated with monitoring access instructions and troubleshooting reference

These updates ensure that future monitoring installations will automatically include the correct authentication configuration, preventing this issue from occurring again.