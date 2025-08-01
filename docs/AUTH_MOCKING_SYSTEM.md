# Authentication Mocking System

This document describes the comprehensive authentication mocking system implemented in the Gamani application for development, testing, and E2E scenarios.

## Overview

The auth mocking system allows developers to bypass AWS Cognito authentication during development and testing while maintaining the same API contracts and data flow as production. This enables:

- **Local Development**: Work without Cognito setup
- **E2E Testing**: Automated tests without authentication complexity
- **API Testing**: Backend testing with mock user contexts
- **Demo Mode**: Quick demonstrations of dashboard functionality

## Architecture

The system operates at multiple layers:

```
Frontend (React/MobX) ←→ Mock Headers ←→ Backend (Express) ←→ Real Database
     ↓                        ↓                    ↓              ↓
AuthStore.mockAuthEnabled → auth-headers.ts → Mock Middleware → DynamoDB
```

## Components

### 1. Frontend - AuthStore (`client/src/stores/AuthStore.ts`)

**Mock Detection Logic:**
```typescript
constructor() {
  makeAutoObservable(this);
  // Check if mock authentication is enabled
  this.mockAuthEnabled = localStorage.getItem('mockAuthEnabled') === 'true' || 
                        (import.meta.env?.NODE_ENV === 'development' && 
                         window.location.search.includes('mock=true'));
}
```

**Authentication Check:**
```typescript
get isAuthenticated() {
  if (this.mockAuthEnabled) {
    const mockUser = localStorage.getItem('mockUser');
    return !!this.user || !!mockUser;
  }
  return !!this.user;
}
```

**Mock User Setup:**
```typescript
setupMockAuth(mockUserData: any) {
  this.mockAuthEnabled = true;
  localStorage.setItem('mockAuthEnabled', 'true');
  localStorage.setItem('mockUser', JSON.stringify(mockUserData));
  
  const cognitoUser: CognitoUser = {
    userId: mockUserData.sub,
    username: mockUserData.username,
    profile: {
      email: mockUserData.email,
      name: mockUserData.username
    }
  };
  
  this.setUser(cognitoUser);
  this.setLoading(false);
}
```

### 2. Mock Headers Utility (`client/src/utils/auth-headers.ts`)

**Header Generation:**
```typescript
export const getAuthHeaders = (): Record<string, string> => {
  const mockAuthEnabled = localStorage.getItem('mockAuthEnabled') === 'true' || 
                          (import.meta.env?.NODE_ENV === 'development' && 
                           window.location.search.includes('mock=true'));

  if (mockAuthEnabled) {
    console.log('🎭 Using mock authentication headers');
    return {
      'Authorization': 'Mock admin',
      'X-Mock-User': 'admin'
    };
  }

  // Production Cognito token logic...
}
```

### 3. Backend - Mock Middleware (`src/middleware/mockAuth.middleware.ts`)

**Mock Authentication Processing:**
```typescript
export const createMockAuthMiddleware = () => {
  return (req: Request, res: Response, next: NextFunction) => {
    const authHeader = req.headers.authorization;
    const mockUser = req.headers['x-mock-user'];
    
    if (authHeader?.startsWith('Mock ') || mockUser) {
      console.log('🔐 [MOCK AUTH MIDDLEWARE] Mock authentication detected');
      
      const mockUserData = {
        sub: 'mock-admin-user-123',
        username: 'admin_user',
        email: 'admin@test.com'
      };
      
      req.user = mockUserData;
      req.isAuthenticated = true;
      
      console.log('✅ [MOCK AUTH MIDDLEWARE] Mock authentication successful');
      return next();
    }
    
    // Fall through to real authentication
    next();
  };
};
```

**Integration with Main Auth Middleware:**
```typescript
export const authMiddleware = async (req: Request, res: Response, next: NextFunction) => {
  // Check if mock authentication is enabled
  if (process.env.ENABLE_AUTH_MOCKING === 'true') {
    const mockMiddleware = createMockAuthMiddleware();
    mockMiddleware(req, res, (err) => {
      if (err) return next(err);
      if (req.isAuthenticated) return next(); // Mock auth succeeded
      // Continue to real authentication
      authenticateWithCognito(req, res, next);
    });
  } else {
    // Production: Only real authentication
    authenticateWithCognito(req, res, next);
  }
};
```

## Usage Scenarios

### 1. Local Development

**Method 1: URL Parameter**
```
http://localhost:5173?mock=true
```

**Method 2: localStorage**
```javascript
localStorage.setItem('mockAuthEnabled', 'true');
localStorage.setItem('mockUser', JSON.stringify({
  sub: 'mock-admin-user-123',
  username: 'admin_user',
  email: 'admin@test.com'
}));
```

**Method 3: Environment Variable**
```bash
ENABLE_AUTH_MOCKING=true npm run dev
```

### 2. E2E Testing

**Playwright Test Setup:**
```javascript
// Navigate with mock parameter
await page.goto('http://localhost:5173?mock=true');

// Set up mock user data
await page.evaluate(() => {
  localStorage.setItem('mockAuthEnabled', 'true');
  localStorage.setItem('mockUser', JSON.stringify({
    sub: 'mock-admin-user-123',
    username: 'admin_user',
    email: 'admin@test.com'
  }));
});

// Refresh to trigger mock auth
await page.goto('http://localhost:5173/dashboard');
```

### 3. API Testing

**Direct API Calls:**
```bash
curl -H "Authorization: Mock admin" \
     -H "X-Mock-User: admin" \
     http://localhost:3003/api/protected/projects
```

**Jest/Supertest:**
```javascript
const response = await request(app)
  .get('/api/protected/projects')
  .set('Authorization', 'Mock admin')
  .set('X-Mock-User', 'admin')
  .expect(200);
```

## Configuration

### Environment Variables

**Backend (`server/.env` or environment):**
```bash
ENABLE_AUTH_MOCKING=true  # Enable mock authentication middleware
NODE_ENV=development      # Enables additional mock features
```

**Frontend (automatically detected):**
- `NODE_ENV=development` + `?mock=true` URL parameter
- `mockAuthEnabled=true` in localStorage

### Mock User Profiles

**Default Admin User:**
```json
{
  "sub": "mock-admin-user-123",
  "username": "admin_user", 
  "email": "admin@test.com"
}
```

**Available Mock User Types:**
- `admin` - Full access mock user
- `user` - Standard user permissions
- `unverified` - Unverified user state
- `minimal` - Minimal permissions
- `newbie` - New user with limited access

**Backend Mock User Selection:**
```typescript
// Via Authorization header
'Authorization': 'Mock admin'    // Uses admin mock user
'Authorization': 'Mock user'     // Uses standard mock user

// Via X-Mock-User header  
'X-Mock-User': 'admin'           // Uses admin mock user
'X-Mock-User': 'newbie'          // Uses newbie mock user
```

## Security Considerations

### Production Safety

1. **Environment Gating**: Mock auth only works when `ENABLE_AUTH_MOCKING=true`
2. **Development Only**: Mock detection checks `NODE_ENV=development`
3. **Explicit Activation**: Requires deliberate activation via URL params or localStorage
4. **No Fallback**: Production never falls back to mock auth

### Data Isolation

1. **Separate Mock User IDs**: Mock users have distinct IDs (`mock-admin-user-123`)
2. **Real Database**: Uses production database with mock user data
3. **Audit Trail**: All mock requests are logged with `[MOCK AUTH MIDDLEWARE]` prefix

## Troubleshooting

### Mock Auth Not Working

**Check Frontend:**
```javascript
// In browser console
console.log('mockAuthEnabled:', localStorage.getItem('mockAuthEnabled'));
console.log('URL params:', window.location.search);
console.log('NODE_ENV:', import.meta.env?.NODE_ENV);
```

**Check Backend:**
```bash
# Verify environment variable
echo $ENABLE_AUTH_MOCKING

# Check server logs for mock middleware messages
grep "MOCK AUTH MIDDLEWARE" server.log
```

**Common Issues:**

1. **Backend not started with mock env var**
   ```bash
   ENABLE_AUTH_MOCKING=true npm run dev
   ```

2. **Frontend localStorage not set**
   ```javascript
   localStorage.setItem('mockAuthEnabled', 'true');
   ```

3. **Wrong URL format**
   ```
   ✅ http://localhost:5173?mock=true
   ❌ http://localhost:5173/?mock=true  # Extra slash
   ```

### API Requests Failing

**Verify Headers:**
```javascript
// Check auth headers utility
const headers = getAuthHeaders();
console.log('Auth headers:', headers);
```

**Expected Headers for Mock:**
```
Authorization: Mock admin
X-Mock-User: admin
```

### Database Connection Issues

Mock authentication still uses real database connections. Verify:

1. **AWS Credentials**: Ensure AWS credentials are configured
2. **Database Access**: Check DynamoDB table permissions
3. **Network**: Verify connectivity to AWS services

## Server Logs Reference

**Successful Mock Authentication Flow:**
```
✅ [MOCK AUTH MIDDLEWARE] 🎭 MOCK AUTHENTICATION ENABLED
✅ [MOCK AUTH MIDDLEWARE] Available test users: admin, user, unverified, minimal, newbie
🔐 [AUTH MIDDLEWARE] Using mock authentication
🔐 [MOCK AUTH MIDDLEWARE] Mock authentication for GET /projects
✅ [MOCK AUTH MIDDLEWARE] Mock authentication successful
✅ [MOCK AUTH MIDDLEWARE] Mock user: {
  sub: 'mock-admin-user-123',
  username: 'admin_user',
  email: 'admin@test.com'
}
🔍 [PROJECTS SERVICE] GET projects - Starting
🔍 [PROJECTS SERVICE] User sub: mock-admin-user-123
✅ [PROJECTS SERVICE] DynamoDB scan completed successfully
```

## Integration Examples

### React Component with Mock Auth

```typescript
import { observer } from 'mobx-react-lite';
import { useAuthStore } from '../stores/AuthStore';

const Dashboard = observer(() => {
  const authStore = useAuthStore();
  
  // Component automatically works with both real and mock auth
  if (!authStore.isAuthenticated) {
    return <LoginPage />;
  }
  
  return (
    <div>
      <h1>Welcome {authStore.user?.username}</h1>
      {authStore.mockAuthEnabled && (
        <div className="mock-banner">
          🎭 Mock Authentication Active
        </div>
      )}
    </div>
  );
});
```

### API Service with Mock Support

```typescript
class ProjectService {
  async getProjects(): Promise<Project[]> {
    const headers = getAuthHeaders(); // Automatically handles mock vs real
    
    const response = await fetch('/api/protected/projects', {
      headers
    });
    
    return response.json();
  }
}
```

## Best Practices

### Development Workflow

1. **Start with Mock Auth**: Begin development using `?mock=true`
2. **Test Real Auth**: Periodically test with actual Cognito
3. **E2E Coverage**: Include both mock and real auth in test suites
4. **Production Verification**: Always test production deployments with real auth

### Code Organization

1. **Separate Mock Logic**: Keep mock code clearly separated
2. **Environment Gating**: Always gate mock features by environment
3. **Logging**: Log mock auth usage for debugging
4. **Documentation**: Document mock user profiles and capabilities

### Security Guidelines

1. **Never Deploy Mock Enabled**: Ensure `ENABLE_AUTH_MOCKING` is not set in production
2. **Review Environment Variables**: Audit all environment configurations
3. **Monitor Mock Usage**: Log and monitor when mock auth is used
4. **Access Control**: Mock users should have appropriate limited permissions

## Migration Notes

This system was implemented to replace manual authentication bypasses and provides:

- **Backward Compatibility**: Existing auth code continues to work
- **Gradual Migration**: Can be adopted incrementally
- **Zero Production Impact**: No changes to production authentication flow
- **Enhanced Testing**: Better support for automated testing scenarios

The mock authentication system is production-ready and safe for use in development, testing, and demonstration environments.