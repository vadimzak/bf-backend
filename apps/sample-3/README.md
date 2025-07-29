# sample-3

A Node.js application deployed at https://sample-3.vadimzak.com

## Configuration

- Port: 3003
- Domain: sample-3.vadimzak.com

## Development

```bash
npm install
npm run dev
```

## Deployment

From project root:
```bash
./scripts/deploy-app.sh sample-3
```

Or from this directory:
```bash
./deploy.sh
```

## Structure

- `server.js` - Main application entry point
- `public/` - Static files served by Express
- `deploy.config` - Deployment configuration
- `docker-compose.prod.yml` - Production Docker configuration