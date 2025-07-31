import { observer } from 'mobx-react-lite';
import { useStore } from '../stores';
import { Navigate } from 'react-router-dom';
import { useState, useEffect } from 'react';
import { useTranslation } from 'react-i18next';
import ProjectManager from '../components/ProjectManager';

const DashboardPage = observer(() => {
  const { authStore, appStore, projectStore, chatStore } = useStore();
  const { t, i18n } = useTranslation();
  const [gamePrompt, setGamePrompt] = useState('');
  const [generatedGame, setGeneratedGame] = useState('');
  const [isGenerating, setIsGenerating] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [showProjectManager, setShowProjectManager] = useState(false);
  const [showChatHistory, setShowChatHistory] = useState(false);
  
  // DEBUG: State for permissions debugging - DO NOT REMOVE
  const [debugItemsResponse, setDebugItemsResponse] = useState<string>('');
  const [debugItemsError, setDebugItemsError] = useState<string>('');
  
  const isRTL = i18n.language === 'he';

  // DEBUG: Function to test items API permissions - DO NOT REMOVE
  const debugItemsAPI = async () => {
    try {
      setDebugItemsError('');
      setDebugItemsResponse('Testing items API...');
      
      const headers = await appStore.getAuthHeaders();
      const response = await fetch('/api/protected/items', {
        method: 'GET',
        headers,
      });

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      const result = await response.json();
      setDebugItemsResponse(`SUCCESS: ${JSON.stringify(result, null, 2)}`);
      console.log('[DEBUG] Items API Response:', result);
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : 'Unknown error';
      setDebugItemsError(`ERROR: ${errorMsg}`);
      console.error('[DEBUG] Items API Error:', error);
    }
  };

  // Load chat history when project changes
  useEffect(() => {
    if (projectStore.currentProject) {
      chatStore.setCurrentProjectId(projectStore.currentProject.id);
    } else {
      chatStore.setCurrentProjectId(null);
    }
  }, [projectStore.currentProject, chatStore]);

  // DEBUG: Auto-test items API on component mount - DO NOT REMOVE
  useEffect(() => {
    if (authStore.isAuthenticated) {
      debugItemsAPI();
    }
  }, [authStore.isAuthenticated]);

  if (!authStore.isAuthenticated) {
    return <Navigate to="/login" replace />;
  }

  const handleSignOut = () => {
    authStore.signOut();
  };

  const generateGame = async () => {
    if (!gamePrompt.trim()) return;
    
    setIsGenerating(true);
    setError(null);
    
    try {
      // Save user message to chat history
      if (projectStore.currentProject) {
        await chatStore.saveMessage(projectStore.currentProject.id, 'user', gamePrompt);
      }

      const headers = await appStore.getAuthHeaders();
      const response = await fetch('/api/protected/ai/generate', {
        method: 'POST',
        headers,
        body: JSON.stringify({ prompt: gamePrompt }),
      });

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      const result = await response.json();
      if (result.success) {
        // Extract HTML content from the response
        let htmlContent = result.data.response;
        
        // Clean up any markdown formatting if present
        if (htmlContent.includes('```html')) {
          htmlContent = htmlContent.replace(/```html\n?/g, '').replace(/```\n?/g, '');
        }
        
        setGeneratedGame(htmlContent);

        // Save assistant message with game code to chat history
        if (projectStore.currentProject) {
          await chatStore.saveMessage(
            projectStore.currentProject.id, 
            'assistant', 
            `Generated game: ${gamePrompt}`, 
            htmlContent
          );
        }
      } else {
        throw new Error(result.error || 'Failed to generate game');
      }
      
      // Clear the input after successful generation
      setGamePrompt('');
    } catch (error) {
      console.error('Failed to generate game:', error);
      setError(error instanceof Error ? error.message : 'Failed to generate game');
    } finally {
      setIsGenerating(false);
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      generateGame();
    }
  };

  return (
    <div className={`min-h-screen bg-gray-900 text-white ${isRTL ? 'rtl' : 'ltr'}`} dir={isRTL ? 'rtl' : 'ltr'}>
      {/* Header */}
      <div className="bg-gray-800 border-b border-gray-700 px-4 py-3">
        <div className="flex justify-between items-center">
          <div className="flex items-center gap-4">
            <h1 className="text-xl font-bold">{t('dashboard.header.title')}</h1>
            <button
              onClick={() => setShowProjectManager(!showProjectManager)}
              className="px-3 py-1 text-sm bg-gray-600 hover:bg-gray-700 rounded transition-colors"
            >
              {showProjectManager ? '📁 ←' : '📁 →'} {t('projects.title')}
            </button>
            {projectStore.currentProject && (
              <span className="text-sm text-blue-300">
                📝 {projectStore.currentProject.name}
              </span>
            )}
          </div>
          <div className="flex items-center gap-4">
            <span className="text-sm text-gray-300">
              {authStore.user?.profile?.name || authStore.user?.username}
            </span>
            <button
              onClick={handleSignOut}
              className="px-3 py-1 text-sm bg-red-600 hover:bg-red-700 rounded transition-colors"
            >
              {t('app.signOut')}
            </button>
          </div>
        </div>
      </div>

      {/* Project Manager Panel */}
      {showProjectManager && (
        <div className="bg-gray-850 border-b border-gray-700 px-4 py-3">
          <ProjectManager />
        </div>
      )}

      {/* DEBUG: Permissions Testing Section - DO NOT REMOVE */}
      <div className="bg-gray-800 border-b border-gray-700 px-4 py-2">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-4">
            <span className="text-sm font-medium text-yellow-400">🔧 DEBUG - Items API Test:</span>
            <button
              onClick={debugItemsAPI}
              className="px-2 py-1 text-xs bg-blue-600 hover:bg-blue-700 rounded"
            >
              Test Again
            </button>
          </div>
          <div className="text-xs">
            {debugItemsError ? (
              <span className="text-red-400">{debugItemsError}</span>
            ) : debugItemsResponse ? (
              <span className="text-green-400">
                {debugItemsResponse.includes('SUCCESS') ? '✅ API Working' : debugItemsResponse}
              </span>
            ) : (
              <span className="text-gray-400">Not tested</span>
            )}
          </div>
        </div>
        {(debugItemsResponse || debugItemsError) && (
          <details className="mt-2">
            <summary className="text-xs text-gray-400 cursor-pointer">Show Details</summary>
            <pre className="text-xs bg-gray-900 p-2 mt-1 rounded overflow-x-auto">
              {debugItemsError || debugItemsResponse}
            </pre>
          </details>
        )}
      </div>

      {/* Main Content - Split Layout */}
      <div className="flex h-[calc(100vh-64px)]">
        {/* Left Panel - Game Preview */}
        <div className="hidden md:flex md:w-1/2 bg-gray-900 flex flex-col">
          <div className="p-4 border-b border-gray-700">
            <h2 className="text-lg font-semibold">{t('dashboard.preview.title')}</h2>
          </div>
          
          <div className="flex-1 p-4">
            {isGenerating ? (
              <div className="flex items-center justify-center h-full">
                <div className="text-center">
                  <div className="animate-spin w-8 h-8 border-4 border-blue-500 border-t-transparent rounded-full mx-auto mb-4"></div>
                  <p className="text-gray-400">{t('dashboard.preview.generating')}</p>
                </div>
              </div>
            ) : generatedGame ? (
              <div className="h-full">
                <iframe
                  srcDoc={generatedGame}
                  className="w-full h-full border border-gray-600 rounded-lg bg-white"
                  sandbox="allow-scripts allow-same-origin"
                  title="Generated Game"
                />
              </div>
            ) : (
              <div className="flex items-center justify-center h-full">
                <div className="text-center text-gray-400">
                  <div className="w-16 h-16 bg-gray-700 rounded-lg mx-auto mb-4 flex items-center justify-center">
                    <svg className="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M14.828 14.828a4 4 0 01-5.656 0M9 10h1m4 0h1m-6 4h.01M19 4a2 2 0 012 2v12a2 2 0 01-2 2H5a2 2 0 01-2-2V6a2 2 0 012-2h14z" />
                    </svg>
                  </div>
                  <p>{t('dashboard.preview.placeholder')}</p>
                </div>
              </div>
            )}
          </div>
        </div>

        {/* Right Panel - Chat Interface */}
        <div className={`w-full md:w-1/2 bg-gray-800 ${isRTL ? 'border-r' : 'border-l'} border-gray-700 flex flex-col`}>
          <div className="p-4 border-b border-gray-700">
            <div className="flex justify-between items-center mb-2">
              <h2 className="text-lg font-semibold">{t('dashboard.chat.title')}</h2>
              {projectStore.currentProject && (
                <div className="flex gap-2">
                  <button
                    onClick={() => setShowChatHistory(!showChatHistory)}
                    className="px-2 py-1 text-xs bg-gray-600 hover:bg-gray-700 rounded transition-colors"
                  >
                    💬 {t('dashboard.chat.history.title')}
                  </button>
                  {chatStore.hasMessages && (
                    <button
                      onClick={async () => {
                        if (window.confirm(t('dashboard.chat.history.confirmClear'))) {
                          try {
                            await chatStore.clearChatHistory(projectStore.currentProject!.id);
                          } catch (error) {
                            console.error('Failed to clear chat history:', error);
                          }
                        }
                      }}
                      className="px-2 py-1 text-xs bg-red-600 hover:bg-red-700 rounded transition-colors"
                    >
                      🗑️ {t('dashboard.chat.history.clearHistory')}
                    </button>
                  )}
                </div>
              )}
            </div>
            <p className="text-sm text-gray-400">
              {t('dashboard.chat.subtitle')}
            </p>
          </div>
          
          <div className="flex-1 p-4 overflow-y-auto">
            <div className="space-y-4">
              {/* Chat History */}
              {showChatHistory && projectStore.currentProject ? (
                <div className="bg-gray-700 rounded-lg p-3">
                  <h3 className="text-sm font-medium mb-3">{t('dashboard.chat.history.title')}</h3>
                  {chatStore.loading ? (
                    <div className="text-center py-4">
                      <div className="animate-spin w-4 h-4 border-2 border-blue-500 border-t-transparent rounded-full mx-auto mb-2"></div>
                      <p className="text-xs text-gray-400">{t('dashboard.chat.history.loadingHistory')}</p>
                    </div>
                  ) : chatStore.hasMessages ? (
                    <div className="space-y-3 max-h-60 overflow-y-auto">
                      {chatStore.currentMessages.map((message) => (
                        <div key={message.id} className="text-sm">
                          <div className="flex items-center gap-2 mb-1">
                            <span className={`font-medium text-xs ${
                              message.role === 'user' ? 'text-blue-300' : 'text-green-300'
                            }`}>
                              {message.role === 'user' ? t('dashboard.chat.history.user') : t('dashboard.chat.history.assistant')}
                            </span>
                            <span className="text-xs text-gray-500">
                              {new Date(message.timestamp).toLocaleString()}
                            </span>
                          </div>
                          <p className="text-gray-300 text-xs bg-gray-800 rounded p-2 break-words">
                            {message.content}
                          </p>
                          {message.gameCode && (
                            <button
                              onClick={() => setGeneratedGame(message.gameCode!)}
                              className="mt-1 px-2 py-1 text-xs bg-blue-600 hover:bg-blue-700 rounded transition-colors"
                            >
                              🎮 View Game
                            </button>
                          )}
                        </div>
                      ))}
                    </div>
                  ) : (
                    <p className="text-sm text-gray-400 text-center py-4">
                      {t('dashboard.chat.history.noHistory')}
                    </p>
                  )}
                </div>
              ) : (
                /* Example prompts when history is hidden */
                <div className="bg-gray-700 rounded-lg p-3">
                  <h3 className="text-sm font-medium mb-2">{t('dashboard.chat.examples.title')}</h3>
                  <ul className="text-sm text-gray-300 space-y-1">
                    <li>• {t('dashboard.chat.examples.memory')}</li>
                    <li>• {t('dashboard.chat.examples.math')}</li>
                    <li>• {t('dashboard.chat.examples.snake')}</li>
                    <li>• {t('dashboard.chat.examples.matching')}</li>
                  </ul>
                </div>
              )}
              
              {/* Error display */}
              {error && (
                <div className="bg-red-900/50 border border-red-700 rounded-lg p-3">
                  <p className="text-red-200 text-sm">{error}</p>
                </div>
              )}

              {/* Chat store error display */}
              {chatStore.error && (
                <div className="bg-red-900/50 border border-red-700 rounded-lg p-3">
                  <p className="text-red-200 text-sm">Chat Error: {chatStore.error}</p>
                </div>
              )}
            </div>
          </div>
          
          {/* Input area */}
          <div className="p-4 border-t border-gray-700">
            <div className="flex gap-2">
              <textarea
                value={gamePrompt}
                onChange={(e) => setGamePrompt(e.target.value)}
                onKeyDown={handleKeyDown}
                placeholder={t('dashboard.chat.placeholder')}
                className="flex-1 p-3 bg-gray-700 border border-gray-600 rounded-lg resize-none focus:outline-none focus:border-blue-500"
                rows={3}
                disabled={isGenerating}
              />
              <button
                onClick={generateGame}
                disabled={isGenerating || !gamePrompt.trim()}
                className="px-6 py-3 bg-blue-600 hover:bg-blue-700 disabled:bg-gray-600 disabled:cursor-not-allowed rounded-lg transition-colors font-medium"
              >
                {isGenerating ? t('dashboard.chat.creating') : t('dashboard.chat.createButton')}
              </button>
            </div>
          </div>
        </div>
      </div>
      
      {/* Mobile Game Preview Modal/Bottom Sheet */}
      {generatedGame && (
        <div className="md:hidden fixed inset-0 bg-black bg-opacity-50 z-50">
          <div className="absolute bottom-0 left-0 right-0 bg-gray-900 rounded-t-lg max-h-[80vh] flex flex-col">
            <div className="p-4 border-b border-gray-700 flex justify-between items-center">
              <h3 className="text-lg font-semibold">{t('dashboard.preview.yourGame')}</h3>
              <button
                onClick={() => setGeneratedGame('')}
                className="text-gray-400 hover:text-white"
              >
                ✕
              </button>
            </div>
            <div className="flex-1 p-4">
              <iframe
                srcDoc={generatedGame}
                className="w-full h-full border border-gray-600 rounded-lg bg-white"
                sandbox="allow-scripts allow-same-origin"
                title="Generated Game"
              />
            </div>
          </div>
        </div>
      )}
    </div>
  );
});

export default DashboardPage;