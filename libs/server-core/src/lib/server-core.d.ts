export declare function serverCore(): string;
export interface AppInfo {
    name: string;
    version: string;
    uptime: number;
    environment: string;
    timestamp: string;
}
export declare function getAppInfo(appName: string, version?: string): AppInfo;
export declare function formatUptime(seconds: number): string;
export declare function createApiResponse<T>(data: T, message?: string): {
    success: boolean;
    data: T;
    message: string;
    timestamp: string;
};
export declare function createErrorResponse(error: string, code?: number): {
    success: boolean;
    error: string;
    code: number;
    timestamp: string;
};
