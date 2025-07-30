export function serverCore(): string {
  return 'server-core';
}

export interface AppInfo {
  name: string;
  version: string;
  uptime: number;
  environment: string;
  timestamp: string;
}

export function getAppInfo(appName: string, version: string = '1.0.0'): AppInfo {
  return {
    name: appName,
    version,
    uptime: process.uptime(),
    environment: process.env.NODE_ENV || 'development',
    timestamp: new Date().toISOString()
  };
}

export function formatUptime(seconds: number): string {
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const secs = Math.floor(seconds % 60);
  
  if (hours > 0) {
    return `${hours}h ${minutes}m ${secs}s`;
  } else if (minutes > 0) {
    return `${minutes}m ${secs}s`;
  } else {
    return `${secs}s`;
  }
}

export function createApiResponse<T>(data: T, message?: string) {
  return {
    success: true,
    data,
    message: message || 'Operation successful',
    timestamp: new Date().toISOString()
  };
}

export function createErrorResponse(error: string, code?: number) {
  return {
    success: false,
    error,
    code: code || 500,
    timestamp: new Date().toISOString()
  };
}
