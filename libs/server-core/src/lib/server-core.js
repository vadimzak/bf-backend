"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.serverCore = serverCore;
exports.getAppInfo = getAppInfo;
exports.formatUptime = formatUptime;
exports.createApiResponse = createApiResponse;
exports.createErrorResponse = createErrorResponse;
function serverCore() {
    return 'server-core';
}
function getAppInfo(appName, version = '1.0.0') {
    return {
        name: appName,
        version,
        uptime: process.uptime(),
        environment: process.env.NODE_ENV || 'development',
        timestamp: new Date().toISOString()
    };
}
function formatUptime(seconds) {
    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    const secs = Math.floor(seconds % 60);
    if (hours > 0) {
        return `${hours}h ${minutes}m ${secs}s`;
    }
    else if (minutes > 0) {
        return `${minutes}m ${secs}s`;
    }
    else {
        return `${secs}s`;
    }
}
function createApiResponse(data, message) {
    return {
        success: true,
        data,
        message: message || 'Operation successful',
        timestamp: new Date().toISOString()
    };
}
function createErrorResponse(error, code) {
    return {
        success: false,
        error,
        code: code || 500,
        timestamp: new Date().toISOString()
    };
}
