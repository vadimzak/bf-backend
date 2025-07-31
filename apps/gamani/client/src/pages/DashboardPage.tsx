import { observer } from 'mobx-react-lite';
import { useStore } from '../stores';
import { Navigate } from 'react-router-dom';
import { useState, useEffect } from 'react';
import ProjectManager from '../components/ProjectManager';

const DashboardPage = observer(() => {
  const { authStore, appStore, projectStore, chatStore } = useStore();
  const [gamePrompt, setGamePrompt] = useState('');
  const [generatedGame, setGeneratedGame] = useState('');
  const [isGenerating, setIsGenerating] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [showProjectManager, setShowProjectManager] = useState(false);
  const [showChatHistory, setShowChatHistory] = useState(false);
  const [isSharing, setIsSharing] = useState(false);
  const [currentGameContext, setCurrentGameContext] = useState<string>('');
  
  // DEBUG: State for permissions debugging - DO NOT REMOVE
  const [debugItemsResponse, setDebugItemsResponse] = useState<string>('');
  const [debugItemsError, setDebugItemsError] = useState<string>('');

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

  // Load chat history when project changes and restore latest game
  useEffect(() => {
    if (projectStore.currentProject) {
      chatStore.setCurrentProjectId(projectStore.currentProject.id);
      
      // Restore the latest game from chat history after messages are loaded
      setTimeout(() => {
        const latestGameMessage = chatStore.currentMessages
          .filter(msg => msg.role === 'assistant' && msg.gameCode)
          .pop();
        
        if (latestGameMessage?.gameCode) {
          setGeneratedGame(latestGameMessage.gameCode);
          setCurrentGameContext(latestGameMessage.gameCode);
        } else {
          setGeneratedGame('');
          setCurrentGameContext('');
        }
      }, 100); // Small delay to ensure messages are loaded
    } else {
      chatStore.setCurrentProjectId(null);
      setGeneratedGame('');
      setCurrentGameContext('');
    }
  }, [projectStore.currentProject, chatStore]);

  // Additional effect to update game when chat messages change
  useEffect(() => {
    if (projectStore.currentProject && chatStore.currentMessages.length > 0) {
      const latestGameMessage = chatStore.currentMessages
        .filter(msg => msg.role === 'assistant' && msg.gameCode)
        .pop();
      
      if (latestGameMessage?.gameCode && latestGameMessage.gameCode !== currentGameContext) {
        setGeneratedGame(latestGameMessage.gameCode);
        setCurrentGameContext(latestGameMessage.gameCode);
      }
    }
  }, [chatStore.currentMessages, projectStore.currentProject, currentGameContext]);

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

  const handleConversation = async () => {
    if (!gamePrompt.trim()) return;
    
    setIsGenerating(true);
    setError(null);
    
    try {
      // Save user message to chat history for persistence
      if (projectStore.currentProject) {
        await chatStore.saveMessage(projectStore.currentProject.id, 'user', gamePrompt);
      }

      // Prepare conversation context from stored chat history
      const conversationContext = chatStore.currentMessages.map(msg => ({
        role: msg.role,
        content: msg.content
      }));

      // Add the current user message to the context
      conversationContext.push({
        role: 'user' as const,
        content: gamePrompt
      });

      const headers = await appStore.getAuthHeaders();
      const response = await fetch('/api/protected/ai/generate', {
        method: 'POST',
        headers,
        body: JSON.stringify({ 
          prompt: gamePrompt,
          conversation: conversationContext,
          currentGame: generatedGame ? currentGameContext : null
        }),
      });

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      const result = await response.json();
      if (result.success) {
        let responseText = result.data.response;
        let hasGameCode = false;
        let gameCode = '';
        
        // Check if response contains game code
        if (responseText.includes('```html') || responseText.includes('<html>') || responseText.includes('<!DOCTYPE html>')) {
          hasGameCode = true;
          
          // Extract HTML content from the response
          if (responseText.includes('```html')) {
            const htmlMatch = responseText.match(/```html\n?([\s\S]*?)```/);
            if (htmlMatch) {
              gameCode = htmlMatch[1].trim();
              responseText = responseText.replace(/```html\n?[\s\S]*?```/g, '').trim();
            }
          } else if (responseText.includes('<html>') || responseText.includes('<!DOCTYPE html>')) {
            // If it's direct HTML without markdown wrapper
            gameCode = responseText;
            responseText = 'I\'ve created a new game for you. You can see it in the left panel.';
          }
          
          // Update the game display
          setGeneratedGame(gameCode);
          setCurrentGameContext(gameCode);
        }
        
        // Save assistant message to chat history for persistence
        if (projectStore.currentProject) {
          await chatStore.saveMessage(
            projectStore.currentProject.id, 
            'assistant', 
            responseText || 'I\'ve created a game for you. Check the left panel!',
            hasGameCode ? gameCode : undefined
          );
        }
      } else {
        throw new Error(result.error || 'Failed to process request');
      }
      
      // Clear the input after successful processing
      setGamePrompt('');
    } catch (error) {
      console.error('Failed to process conversation:', error);
      setError(error instanceof Error ? error.message : 'Failed to process request');
    } finally {
      setIsGenerating(false);
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      handleConversation();
    }
  };

  const shareGame = async () => {
    if (!generatedGame) return;
    
    setIsSharing(true);
    
    try {
      const gameTitle = `Game created: ${new Date().toLocaleString()}`;
      const headers = await appStore.getAuthHeaders();
      
      const response = await fetch('/api/protected/games/share', {
        method: 'POST',
        headers,
        body: JSON.stringify({
          title: gameTitle,
          content: generatedGame,
          description: gamePrompt
        })
      });

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      const result = await response.json();
      
      if (result.success) {
        const shareUrl = result.data.shareUrl;
        
        // Copy URL to clipboard
        try {
          await navigator.clipboard.writeText(shareUrl);
          alert(`Game shared successfully! URL: ${shareUrl}`);
        } catch (clipboardError) {
          // Fallback: show URL in prompt for manual copying
          prompt('Copy this URL to share your game:', shareUrl);
        }
      } else {
        throw new Error(result.error || 'Failed to share game');
      }
    } catch (error) {
      console.error('Failed to share game:', error);
      alert('Failed to share game. Please try again.');
    } finally {
      setIsSharing(false);
    }
  };

  return (
    <div className="min-h-screen bg-gray-900 text-white">
      {/* Header */}
      <div className="bg-gray-800 border-b border-gray-700 px-4 py-3">
        <div className="flex justify-between items-center">
          <div className="flex items-center gap-4">
            <button
              onClick={handleSignOut}
              className="px-3 py-1 text-sm bg-red-600 hover:bg-red-700 rounded transition-colors"
            >
              Sign Out
            </button>
            <button
              onClick={() => setShowProjectManager(!showProjectManager)}
              className="px-3 py-1 text-sm bg-gray-600 hover:bg-gray-700 rounded transition-colors"
            >
              {showProjectManager ? '📁 ←' : '📁 →'} Projects
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
            <h1 className="text-xl font-bold">Gamani - Game Creator</h1>
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
            <div className="flex justify-between items-center">
              <h2 className="text-lg font-semibold">Game Preview</h2>
              {generatedGame && (
                <button
                  onClick={shareGame}
                  disabled={isSharing}
                  className="px-3 py-1 text-sm bg-green-600 hover:bg-green-700 disabled:bg-gray-600 disabled:cursor-not-allowed rounded transition-colors"
                >
                  {isSharing ? 'Sharing...' : 'Share'}
                </button>
              )}
            </div>
          </div>
          
          <div className="flex-1 p-4">
            {isGenerating ? (
              <div className="flex items-center justify-center h-full">
                <div className="text-center">
                  <div className="animate-spin w-8 h-8 border-4 border-blue-500 border-t-transparent rounded-full mx-auto mb-4"></div>
                  <p className="text-gray-400">Creating your game...</p>
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
                  <p>Your generated game will appear here</p>
                </div>
              </div>
            )}
          </div>
        </div>

        {/* Right Panel - Chat Interface */}
        <div className="w-full md:w-1/2 bg-gray-800 border-l border-gray-700 flex flex-col">
          <div className="p-4 border-b border-gray-700">
            <div className="flex justify-between items-center mb-2">
              {projectStore.currentProject && (
                <div className="flex gap-2">
                  <button
                    onClick={() => setShowChatHistory(!showChatHistory)}
                    className="px-2 py-1 text-xs bg-gray-600 hover:bg-gray-700 rounded transition-colors"
                  >
                    💬 Chat History
                  </button>
                  {chatStore.hasMessages && (
                    <button
                      onClick={async () => {
                        if (window.confirm('Are you sure you want to clear the chat history?')) {
                          try {
                            await chatStore.clearChatHistory(projectStore.currentProject!.id);
                          } catch (error) {
                            console.error('Failed to clear chat history:', error);
                          }
                        }
                      }}
                      className="px-2 py-1 text-xs bg-red-600 hover:bg-red-700 rounded transition-colors"
                    >
                      🗑️ Clear History
                    </button>
                  )}
                </div>
              )}
            </div>
          </div>
          
          {/* Chat Messages Area - ChatGPT Style */}
          <div className="flex-1 flex flex-col overflow-hidden">
            {/* Chat Messages */}
            <div className="flex-1 overflow-y-auto p-4 space-y-4">
              {/* Error display at top */}
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

              {/* Current Conversation - ChatGPT Style */}
              {chatStore.currentMessages.length > 0 ? (
                <div className="space-y-4">
                  {chatStore.currentMessages.map((message) => (
                    <div key={message.id} className={`flex ${message.role === 'user' ? 'justify-end' : 'justify-start'}`}>
                      <div className={`max-w-[80%] rounded-lg p-3 ${
                        message.role === 'user' 
                          ? 'bg-blue-600 text-white' 
                          : 'bg-gray-700 text-gray-200'
                      }`}>
                        <div className="text-sm">
                          <div className="flex items-center gap-2 mb-1 justify-start">
                            <span className={`font-medium text-xs ${
                              message.role === 'user' ? 'text-blue-100' : 'text-green-300'
                            }`}>
                              {message.role === 'user' ? 'You' : 'Gamani'}
                            </span>
                            <span className="text-xs opacity-70">
                              {new Date(message.timestamp).toLocaleString()}
                            </span>
                          </div>
                          <p className="break-words">
                            {message.content}
                          </p>
                          {message.gameCode && (
                            <div className="mt-2 px-2 py-1 text-xs bg-green-600 rounded">
                              🎮 Game Generated
                            </div>
                          )}
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              ) : (
                <div className="flex items-center justify-center h-full">
                  <p className="text-gray-400 text-center">
                    Start a conversation with Gamani...
                  </p>
                </div>
              )}

              {/* Loading indicator for generation */}
              {isGenerating && (
                <div className="flex justify-start">
                  <div className="bg-gray-700 rounded-lg p-3 max-w-[80%]">
                    <div className="flex items-center gap-2">
                      <div className="animate-spin w-4 h-4 border-2 border-blue-500 border-t-transparent rounded-full"></div>
                      <p className="text-gray-300 text-sm">
                        Creating your game...
                      </p>
                    </div>
                  </div>
                </div>
              )}
            </div>
          </div>
          
          {/* Input area - Fixed at bottom */}
          <div className="p-4 border-t border-gray-700 bg-gray-800">
            <div className="flex gap-2">
              <textarea
                value={gamePrompt}
                onChange={(e) => setGamePrompt(e.target.value)}
                onKeyDown={handleKeyDown}
                placeholder="Ask something or request to create a game..."
                className="flex-1 p-3 bg-gray-700 border border-gray-600 rounded-lg resize-none focus:outline-none focus:border-blue-500"
                rows={3}
                disabled={isGenerating}
              />
              <button
                onClick={handleConversation}
                disabled={isGenerating || !gamePrompt.trim()}
                className="px-6 py-3 bg-blue-600 hover:bg-blue-700 disabled:bg-gray-600 disabled:cursor-not-allowed rounded-lg transition-colors font-medium"
              >
                {isGenerating ? 'Creating...' : 'Send'}
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
              <h3 className="text-lg font-semibold">Your Game</h3>
              <div className="flex gap-2 items-center">
                <button
                  onClick={shareGame}
                  disabled={isSharing}
                  className="px-3 py-1 text-sm bg-green-600 hover:bg-green-700 disabled:bg-gray-600 disabled:cursor-not-allowed rounded transition-colors"
                >
                  {isSharing ? 'Sharing...' : 'Share'}
                </button>
                <button
                  onClick={() => setGeneratedGame('')}
                  className="text-gray-400 hover:text-white"
                >
                  ✕
                </button>
              </div>
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