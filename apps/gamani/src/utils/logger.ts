const timestamp = () => new Date().toISOString();

export const log = (level: string, message: string, ...args: any[]) => {
  console.log(`[${timestamp()}] ${level} ${message}`, ...args);
};

export const createLogger = (component: string) => ({
  info: (message: string, ...args: any[]) => log(`ℹ️ [${component}]`, message, ...args),
  success: (message: string, ...args: any[]) => log(`✅ [${component}]`, message, ...args),
  error: (message: string, ...args: any[]) => log(`❌ [${component}]`, message, ...args),
  warning: (message: string, ...args: any[]) => log(`⚠️ [${component}]`, message, ...args),
  debug: (message: string, ...args: any[]) => log(`🔧 [${component}]`, message, ...args),
  request: (message: string, ...args: any[]) => log(`📡 [${component}]`, message, ...args),
  auth: (message: string, ...args: any[]) => log(`🔐 [${component}]`, message, ...args),
  search: (message: string, ...args: any[]) => log(`🔍 [${component}]`, message, ...args),
  chat: (message: string, ...args: any[]) => log(`💬 [${component}]`, message, ...args),
  ai: (message: string, ...args: any[]) => log(`🤖 [${component}]`, message, ...args),
  startup: (message: string, ...args: any[]) => log(`🚀 [${component}]`, message, ...args)
});