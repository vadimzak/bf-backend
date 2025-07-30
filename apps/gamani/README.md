# Gamani - Full-Stack TypeScript Application

A modern full-stack application built with the specified tech stack:

## Backend Technology Stack
- **Runtime**: Node.js + TypeScript
- **Framework**: Express.js
- **Authentication**: Firebase Admin SDK
- **Database**: DynamoDB
- **AI**: Google Generative AI (@google/genai)
- **Build**: TypeScript compiler

## Frontend Technology Stack
- **Framework**: React 18 + TypeScript
- **Build Tool**: Vite
- **State Management**: MobX with decorators
- **Authentication**: Firebase Auth (Google OAuth)
- **Styling**: shadcn/ui + Tailwind CSS

## Project Structure

```
apps/gamani/
├── src/                    # Backend TypeScript source
│   └── server.ts          # Main Express server
├── client/                # Frontend React application
│   ├── src/
│   │   ├── stores/        # MobX stores
│   │   ├── pages/         # React pages
│   │   ├── config/        # Firebase config
│   │   └── App.tsx        # Main React app
│   ├── package.json       # Frontend dependencies
│   └── vite.config.ts     # Vite configuration
├── k8s/                   # Kubernetes manifests
├── Dockerfile             # Multi-stage Docker build
├── package.json           # Backend dependencies
├── tsconfig.json          # TypeScript config
└── project.json           # NX project configuration
```

## Development

### Backend Development
```bash
# From apps/gamani directory
npm install
npm run dev
```

### Frontend Development
```bash
# From apps/gamani/client directory
npm install
npm run dev
```

### Full Development (with NX)
```bash
# From project root
nx run gamani:dev          # Start backend
nx run gamani:dev-client   # Start frontend
```

## Environment Setup

1. Copy environment files:
```bash
cp .env.example .env
cp client/.env.example client/.env
```

2. Configure Firebase:
   - Create a Firebase project
   - Enable Google Authentication
   - Download service account key for backend
   - Add Firebase config to frontend .env

3. Configure Google AI:
   - Get Google AI API key
   - Add to backend .env

4. Configure AWS:
   - Ensure AWS credentials are configured
   - Create DynamoDB table: `gamani-items`

## Building and Deployment

### Build
```bash
nx run gamani:build-all    # Build both backend and frontend
```

### Docker
```bash
nx run gamani:docker-build # Build Docker image
```

### Kubernetes Deployment
```bash
# Deploy to Kubernetes cluster
./scripts/k8s/deploy-app.sh gamani
```

## Features

- **Authentication**: Google OAuth with Firebase
- **Database**: DynamoDB integration for data persistence
- **AI Integration**: Google Generative AI for text generation
- **Modern UI**: Dark mode shadcn/ui components
- **State Management**: MobX with decorators
- **TypeScript**: Full type safety across the stack
- **Containerized**: Docker and Kubernetes ready

## API Endpoints

### Public
- `GET /` - Frontend application
- `GET /health` - Health check

### Authenticated
- `POST /api/auth/verify` - Verify Firebase token
- `GET /api/protected/items` - Get user items
- `POST /api/protected/items` - Create new item
- `POST /api/protected/ai/generate` - Generate AI content

## URL

Once deployed: https://gamani.vadimzak.com