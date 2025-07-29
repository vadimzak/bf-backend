# sample-7

A Node.js application deployed at https://sample-7.vadimzak.com

## Configuration

- Port: 3007
- Domain: sample-7.vadimzak.com

## Development

```bash
npm install
npm run dev
```

## Deployment

From project root:
```bash
./scripts/deploy-app.sh sample-7
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