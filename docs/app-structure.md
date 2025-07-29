# App Structure

All apps in this monorepo have identical structure, making it easy to:
- Clone any app as a template for a new app
- Delete any app without affecting others
- Deploy any app with the same commands

## Standard App Structure

```
apps/<app-name>/
├── .env.example          # Example environment variables
├── .env.production       # Production environment variables
├── .gitignore           # Git ignore file
├── deploy.config        # Deployment configuration (port & domain)
├── deploy.sh            # Deployment wrapper script
├── docker-compose.prod.yml # Production Docker configuration
├── Dockerfile           # Docker image definition
├── package.json         # Node.js dependencies
├── project.json         # NX project configuration
├── README.md            # App documentation
├── server.js            # Main application entry point
└── public/              # Static files
    ├── index.html       # Main HTML page
    ├── styles.css       # CSS styles
    └── app.js           # Client-side JavaScript
```

## Creating a New App from Existing

### Option 1: Use the automated script
```bash
./scripts/add-new-app.sh my-new-app
```

### Option 2: Clone and modify manually
```bash
# Copy an existing app
cp -r apps/sample-2 apps/my-new-app

# Update configuration
cd apps/my-new-app

# Edit deploy.config
APP_PORT=3004
APP_DOMAIN=my-new-app.vadimzak.com

# Update package.json name and description
# Update server.js service name
# Update HTML title and content

# Deploy
./deploy.sh
```

## Key Files to Modify

When cloning an app, only these files need updates:

1. **deploy.config** - Change port and domain
2. **package.json** - Update name and description
3. **server.js** - Update service name in health check
4. **public/index.html** - Update title and content
5. **README.md** - Update documentation

## Deployment

All apps deploy the same way:
```bash
# From project root
./scripts/deploy-app.sh <app-name>

# Or from app directory
cd apps/<app-name>
./deploy.sh
```