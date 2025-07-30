// Client-side utilities inspired by server-core

export interface HealthResponse {
  success: boolean;
  data: {
    name: string;
    version: string;
    uptime: number;
    uptimeFormatted: string;
    environment: string;
    timestamp: string;
    status: string;
    serverCore: string;
    services: {
      firebase: boolean;
      dynamodb: boolean;
      googleAI: boolean;
    };
  };
  message: string;
  timestamp: string;
}

export interface ApiResponse<T> {
  success: boolean;
  data?: T;
  error?: string;
  message?: string;
  code?: number;
  timestamp: string;
}

// Client-side version of formatUptime from server-core
export function formatUptimeLocal(seconds: number): string {
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

export async function fetchHealthStatus(): Promise<HealthResponse> {
  const response = await fetch('/health');
  return response.json();
}

export function displayServiceStatus(services: Record<string, boolean>): string {
  const working = Object.entries(services)
    .filter(([_, status]) => status)
    .map(([name]) => name);
  
  const broken = Object.entries(services)
    .filter(([_, status]) => !status)
    .map(([name]) => name);
  
  if (broken.length === 0) {
    return `All services online: ${working.join(', ')}`;
  } else {
    return `${working.length}/${Object.keys(services).length} services online. Issues: ${broken.join(', ')}`;
  }
}