# sample-app

A Node.js application deployed at https://sample.vadimzak.com

## Configuration

- Port: 3001
- Domain: sample.vadimzak.com

## Development

```bash
npm install
npm run dev
```

## Deployment

From project root:
```bash
./scripts/k8s/deploy-app.sh sample-app
```

## Structure

- `server.js` - Main application entry point
- `public/` - Static files served by Express
- `Dockerfile` - Container definition
- `k8s/` - Kubernetes manifests