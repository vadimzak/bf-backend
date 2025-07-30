# sample-6

A Node.js application deployed at https://sample-6.vadimzak.com

## Configuration

- Port: 3006
- Domain: sample-6.vadimzak.com

## Development

```bash
npm install
npm run dev
```

## Deployment

From project root:
```bash
./scripts/k8s/deploy-app.sh sample-6
```

## Structure

- `server.js` - Main application entry point
- `public/` - Static files served by Express
- `Dockerfile` - Container definition
- `k8s/` - Kubernetes manifests