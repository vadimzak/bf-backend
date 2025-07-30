# Secondary IP Default Behavior Change

## Summary
As of July 2025, secondary IP setup is now **ENABLED BY DEFAULT** when bootstrapping Kubernetes clusters. This ensures HTTPS works on the standard port 443 out of the box.

## What Changed

### Before
```bash
# Had to explicitly enable secondary IP
./scripts/k8s/bootstrap-cluster.sh --with-secondary-ip
./scripts/k8s/quick-start-full.sh --with-secondary-ip
```

### After  
```bash
# Secondary IP is enabled by default
./scripts/k8s/bootstrap-cluster.sh
./scripts/k8s/quick-start-full.sh

# To disable (and save $3.60/month)
./scripts/k8s/bootstrap-cluster.sh --no-secondary-ip
./scripts/k8s/quick-start-full.sh --no-secondary-ip
```

## Why This Change?

1. **Better User Experience**: HTTPS on port 443 works by default
2. **Standard Expectations**: Users expect HTTPS to work on standard ports
3. **Minimal Cost**: Only ~$3.60/month for the secondary Elastic IP
4. **Opt-out Available**: Users who want to save money can still disable it

## Impact

### With Secondary IP (Default)
- ✅ `https://app.vadimzak.com` - Works on standard port 443
- ✅ `http://app.vadimzak.com` - Works on standard port 80
- 💰 Additional cost: ~$3.60/month

### Without Secondary IP (Opt-out)
- ❌ `https://app.vadimzak.com` - Does NOT work
- ✅ `https://app.vadimzak.com:30443` - Works on non-standard port
- ✅ `http://app.vadimzak.com` - Works on standard port 80
- 💰 No additional cost

## Migration

### For Existing Scripts
The `--with-secondary-ip` flag is kept for backwards compatibility but is no longer needed:

```bash
# Still works but redundant
./scripts/k8s/bootstrap-cluster.sh --with-secondary-ip

# Preferred (same result)
./scripts/k8s/bootstrap-cluster.sh
```

### For CI/CD Pipelines
Update your pipelines to either:
1. Remove `--with-secondary-ip` (recommended)
2. Add `--no-secondary-ip` if you want to save costs

## Cost Considerations

The secondary IP adds ~$3.60/month to your AWS bill. This is a small price for having HTTPS work on the standard port. However, if you want to minimize costs:

```bash
# Bootstrap without secondary IP
./scripts/k8s/bootstrap-cluster.sh --no-secondary-ip

# Your apps will be accessible at:
# - http://app.vadimzak.com (standard port 80)
# - https://app.vadimzak.com:30443 (non-standard port)
```

## Technical Details

The change was implemented by:
1. Setting `SETUP_SECONDARY_IP=true` by default in bootstrap scripts
2. Changing the flag from opt-in (`--with-secondary-ip`) to opt-out (`--no-secondary-ip`)
3. Updating help messages and documentation

No changes were made to the underlying secondary IP implementation, which still uses:
- Secondary private IP on the EC2 instance
- Elastic IP association
- iptables PREROUTING redirect (443 → 8443)
- HAProxy listening on port 8443