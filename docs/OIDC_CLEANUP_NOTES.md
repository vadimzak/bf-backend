# OIDC Provider Cleanup Notes

## Current Status (July 31, 2025)

After fixing the OIDC verification issues, we now have two OIDC providers:

1. **S3-based (Active)**: `arn:aws:iam::363397505860:oidc-provider/bf-kops-oidc-store.s3.il-central-1.amazonaws.com`
2. **Internal API (Legacy)**: `arn:aws:iam::363397505860:oidc-provider/api.internal.c02.vadimzak.com`

## Currently Active Roles

### Using S3-based OIDC Provider ✅
- `gamani-app-role` - Manual IRSA role for Gamani application
- `gamani-service-account.apps.sa.c02.vadimzak.com` - KOPS-generated role

Both roles are successfully using the S3-based OIDC provider with:
- **Issuer**: `https://bf-kops-oidc-store.s3.il-central-1.amazonaws.com`
- **Audience**: `kubernetes.svc.default`
- **Subject**: `system:serviceaccount:apps:gamani-service-account`

## Legacy OIDC Provider Status

The internal API OIDC provider (`api.internal.c02.vadimzak.com`) appears to be unused:
- No current roles reference it in trust policies
- JWT tokens now use the S3-based issuer
- Cluster configuration updated to use S3-based serviceAccountIssuer

## Cleanup Recommendation

The legacy OIDC provider can be safely removed once we verify:
1. All applications are working with S3-based OIDC
2. No system components reference the old provider
3. Backup procedures are in place

### Manual Cleanup Command (Future)
```bash
# ONLY run this after thorough verification
aws iam delete-open-id-connect-provider \
  --open-id-connect-provider-arn arn:aws:iam::363397505860:oidc-provider/api.internal.c02.vadimzak.com \
  --profile bf
```

## Verification Commands

```bash
# Check current OIDC providers
aws iam list-open-id-connect-providers --profile bf

# Verify JWT token issuer
kubectl exec -n apps deployment/gamani -- sh -c 'TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token); echo $TOKEN | cut -d"." -f2 | base64 -d 2>/dev/null' | grep iss

# Test application functionality
curl -s https://gamani.vadimzak.com/health | jq '.data.services'
```

## Decision: Keep for Now

Given that the system is working perfectly and this is a production environment, we'll keep both OIDC providers for now. The legacy provider consumes minimal resources and provides a safety net.

Future cleanup can be performed during maintenance windows after extended verification.