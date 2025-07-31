import { observer } from 'mobx-react-lite';
import { useStore } from '../stores';
import { Navigate } from 'react-router-dom';
import { useState, useEffect, useRef } from 'react';
import ProjectManager from '../components/ProjectManager';

const DashboardPage = observer(() => {
  const { authStore, appStore, projectStore, chatStore } = useStore();
  const [gamePrompt, setGamePrompt] = useState('');
  const [generatedGame, setGeneratedGame] = useState('');
  const [isGenerating, setIsGenerating] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);
  const [showChatHistory, setShowChatHistory] = useState(false);
  const [isSharing, setIsSharing] = useState(false);
  const [currentGameContext, setCurrentGameContext] = useState<string>('');
  const [hasInitialized, setHasInitialized] = useState(false);
  const [activePanel, setActivePanel] = useState<'chat' | 'preview'>('chat');
  const [showGameModal, setShowGameModal] = useState(false);
  const [touchStart, setTouchStart] = useState<number | null>(null);
  const [touchEnd, setTouchEnd] = useState<number | null>(null);
  const messagesEndRef = useRef<HTMLDivElement>(null);
  
  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  };

  // Handle touch events for swipe navigation
  const handleTouchStart = (e: React.TouchEvent) => {
    setTouchEnd(null); // otherwise the swipe is fired even with usual touch events
    setTouchStart(e.targetTouches[0].clientX);
  };

  const handleTouchMove = (e: React.TouchEvent) => {
    setTouchEnd(e.targetTouches[0].clientX);
  };

  const handleTouchEnd = () => {
    if (!touchStart || !touchEnd) return;
    
    const distance = touchStart - touchEnd;
    const isLeftSwipe = distance > 50;
    const isRightSwipe = distance < -50;

    if (isLeftSwipe && activePanel === 'chat' && generatedGame) {
      setActivePanel('preview');
      setShowGameModal(true);
    }
    if (isRightSwipe && activePanel === 'preview') {
      setActivePanel('chat');
      setShowGameModal(false);
    }
  };

  // Scroll to bottom when messages change
  useEffect(() => {
    scrollToBottom();
  }, [chatStore.currentMessages.length, isGenerating]);

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

  // Initialize the component (no special auto-open logic needed since there will always be a project)
  useEffect(() => {
    if (!hasInitialized && !projectStore.loading) {
      setHasInitialized(true);
    }
  }, [projectStore.loading, hasInitialized]);


  if (!authStore.isAuthenticated) {
    return <Navigate to="/login" replace />;
  }

  const handleSignOut = () => {
    authStore.signOut();
  };

  const handleConversation = async () => {
    if (!gamePrompt.trim()) return;
    
    const currentPrompt = gamePrompt;
    setIsGenerating(true);
    setError(null);
    
    // Clear the input immediately for better UX
    setGamePrompt('');
    
    try {
      // Optimistic UI update - add user message to UI immediately
      if (projectStore.currentProject) {
        // Create optimistic message for immediate UI feedback
        const optimisticMessage = {
          id: `temp-${Date.now()}`,
          projectId: projectStore.currentProject.id,
          role: 'user' as const,
          content: currentPrompt,
          timestamp: new Date().toISOString()
        };
        
        // Add to UI immediately
        chatStore.addMessage(optimisticMessage);
        
        // Save to database in the background (skip adding to UI since we already have optimistic version)
        try {
          const userMessage = await chatStore.saveMessage(projectStore.currentProject.id, 'user', currentPrompt, undefined, true);
          
          // Replace optimistic message with real one from server
          if (userMessage) {
            chatStore.replaceMessage(optimisticMessage.id, userMessage);
          }
        } catch (saveError) {
          console.error('Failed to save user message:', saveError);
          // Keep the optimistic message even if save fails
        }
      }

      // Prepare conversation context from stored chat history
      const conversationContext = chatStore.currentMessages.map(msg => ({
        role: msg.role,
        content: msg.content
      }));

      const headers = await appStore.getAuthHeaders();
      const response = await fetch('/api/protected/ai/generate', {
        method: 'POST',
        headers,
        body: JSON.stringify({ 
          prompt: currentPrompt,
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
    } catch (error) {
      console.error('Failed to process conversation:', error);
      setError(error instanceof Error ? error.message : 'Failed to process request');
      // Restore the input text if there was an error
      setGamePrompt(currentPrompt);
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

  const openGameFullScreen = () => {
    if (!generatedGame) return;
    
    const newWindow = window.open('', '_blank');
    if (newWindow) {
      newWindow.document.open();
      newWindow.document.write(generatedGame);
      newWindow.document.close();
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
          <div className="flex items-center gap-2 md:gap-4">
            <h1 className="text-lg md:text-xl font-bold truncate">Gamani</h1>
            <button
              onClick={() => setSidebarCollapsed(!sidebarCollapsed)}
              className="px-2 md:px-3 py-1 text-xs md:text-sm bg-gray-600 hover:bg-gray-700 rounded transition-colors"
            >
              <span className="hidden sm:inline">{sidebarCollapsed ? '📁 →' : '📁 ←'} Projects</span>
              <span className="sm:hidden">📁</span>
            </button>
            {projectStore.currentProject && (
              <span className="text-xs md:text-sm text-blue-300 truncate max-w-24 md:max-w-none">
                📝 {projectStore.currentProject.name}
              </span>
            )}
          </div>
          <div className="flex items-center gap-2 md:gap-4">
            <span className="text-xs md:text-sm text-gray-300 hidden sm:block">
              {authStore.user?.profile?.name || authStore.user?.username}
            </span>
            <button
              onClick={handleSignOut}
              className="px-2 md:px-3 py-1 text-xs md:text-sm bg-red-600 hover:bg-red-700 rounded transition-colors"
            >
              <span className="hidden sm:inline">Sign Out</span>
              <span className="sm:hidden">Exit</span>
            </button>
          </div>
        </div>
        
        {/* Mobile Panel Switcher */}
        <div className="md:hidden mt-3 flex bg-gray-700 rounded-lg p-1">
          <button
            onClick={() => setActivePanel('chat')}
            className={`flex-1 py-2 px-4 text-sm font-medium rounded-md transition-colors ${
              activePanel === 'chat'
                ? 'bg-blue-600 text-white'
                : 'text-gray-300 hover:text-white hover:bg-gray-600'
            }`}
          >
            💬 Chat
          </button>
          <button
            onClick={() => {
              setActivePanel('preview');
              if (generatedGame) setShowGameModal(true);
            }}
            className={`flex-1 py-2 px-4 text-sm font-medium rounded-md transition-colors relative ${
              activePanel === 'preview'
                ? 'bg-green-600 text-white'
                : 'text-gray-300 hover:text-white hover:bg-gray-600'
            }`}
          >
            🎮 Preview
            {generatedGame && (
              <span className="absolute -top-1 -right-1 w-3 h-3 bg-green-500 rounded-full border border-gray-800"></span>
            )}
          </button>
        </div>
      </div>

      {/* Main Content - 3-panel Layout with Sidebar */}
      <div className="flex h-[calc(100vh-64px)]">
        {/* Left Sidebar - Projects */}
        <div className={`bg-gray-800 border-r border-gray-700 transition-all duration-300 ${
          sidebarCollapsed ? 'w-0 overflow-hidden' : 'w-80'
        }`}>
          {!sidebarCollapsed && (
            <div className="p-4 h-full overflow-y-auto">
              <ProjectManager />
            </div>
          )}
        </div>
        {/* Center Panel - Game Preview */}
        <div className="hidden md:flex flex-1 bg-gray-900 flex flex-col">
          <div className="p-4 border-b border-gray-700">
            <div className="flex justify-between items-center">
              <h2 className="text-lg font-semibold">Game Preview</h2>
              {generatedGame && (
                <div className="flex gap-2">
                  <button
                    onClick={openGameFullScreen}
                    className="px-3 py-1 text-sm bg-blue-600 hover:bg-blue-700 rounded transition-colors"
                    title="Open game in new tab"
                  >
                    ⛶ Full Screen
                  </button>
                  <button
                    onClick={shareGame}
                    disabled={isSharing}
                    className="px-3 py-1 text-sm bg-green-600 hover:bg-green-700 disabled:bg-gray-600 disabled:cursor-not-allowed rounded transition-colors"
                  >
                    {isSharing ? 'Sharing...' : 'Share'}
                  </button>
                </div>
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
        <div 
          className={`w-full md:flex-1 bg-gray-800 md:border-l border-gray-700 flex flex-col ${
            activePanel === 'chat' ? 'flex' : 'hidden md:flex'
          }`}
          onTouchStart={handleTouchStart}
          onTouchMove={handleTouchMove}
          onTouchEnd={handleTouchEnd}
        >
          <div className="p-3 md:p-4 border-b border-gray-700">
            <div className="flex justify-between items-center mb-2">
              <div className="flex gap-1 md:gap-2 flex-wrap">
                <button
                  onClick={() => setShowChatHistory(!showChatHistory)}
                  className="px-2 py-1 text-xs bg-gray-600 hover:bg-gray-700 rounded transition-colors touch-manipulation"
                >
                  <span className="hidden sm:inline">💬 Chat History</span>
                  <span className="sm:hidden">💬 History</span>
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
                    className="px-2 py-1 text-xs bg-red-600 hover:bg-red-700 rounded transition-colors touch-manipulation"
                  >
                    <span className="hidden sm:inline">🗑️ Clear History</span>
                    <span className="sm:hidden">🗑️ Clear</span>
                  </button>
                )}
              </div>
            </div>
          </div>
          
          {/* Chat Messages Area - ChatGPT Style */}
          <div className="flex-1 flex flex-col overflow-hidden">
            {/* Chat Messages */}
            <div className="flex-1 overflow-y-auto p-3 md:p-4 space-y-3 md:space-y-4">
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

              {/* Chat History Panel */}
              {showChatHistory && (
                <div className="bg-gray-800 border border-gray-700 rounded-lg p-4 mb-4">
                  <div className="flex justify-between items-center mb-3">
                    <h4 className="text-sm font-medium text-gray-300">Conversation History</h4>
                    <button
                      onClick={() => setShowChatHistory(false)}
                      className="text-gray-400 hover:text-white text-sm"
                    >
                      ✕
                    </button>
                  </div>
                  
                  {chatStore.currentMessages.length > 0 ? (
                    <div className="space-y-2 max-h-40 overflow-y-auto">
                      {chatStore.currentMessages.map((message, _index) => (
                        <div key={message.id} className="text-xs p-3 bg-gray-700 rounded-lg border border-gray-600 hover:bg-gray-650 transition-colors">
                          <div className="flex justify-between items-start">
                            <span className={`font-medium ${message.role === 'user' ? 'text-blue-300' : 'text-green-300'}`}>
                              {message.role === 'user' ? 'You' : 'Gamani'}:
                            </span>
                            <span className="text-gray-400">
                              {new Date(message.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                            </span>
                          </div>
                          <div className="text-gray-200 mt-1 line-clamp-2">
                            {message.content}
                          </div>
                          {message.gameCode && (
                            <div className="text-green-300 text-xs mt-1">🎮 Game Generated</div>
                          )}
                        </div>
                      ))}
                    </div>
                  ) : (
                    <div className="text-sm text-gray-400 text-center py-6 bg-gray-700/50 rounded-lg border border-gray-600">
                      <div className="mb-2">💬</div>
                      <div>No conversation history yet</div>
                      <div className="text-xs text-gray-500 mt-1">Start chatting to see your message history</div>
                    </div>
                  )}
                </div>
              )}


              {/* Current Conversation - Enhanced ChatGPT Style */}
              {chatStore.currentMessages.length > 0 ? (
                <div className="space-y-4 md:space-y-6">
                  {chatStore.currentMessages.map((message) => (
                    <div key={message.id} className={`flex ${message.role === 'user' ? 'justify-end' : 'justify-start'} group`}>
                      <div className={`max-w-[90%] md:max-w-[85%] ${message.role === 'user' ? 'order-2' : 'order-1'}`}>
                        {/* Avatar and Name */}
                        <div className={`flex items-center gap-1.5 md:gap-2 mb-1.5 md:mb-2 ${message.role === 'user' ? 'justify-end' : 'justify-start'}`}>
                          <div className={`w-5 h-5 md:w-6 md:h-6 rounded-full flex items-center justify-center text-xs font-bold ${
                            message.role === 'user' 
                              ? 'bg-blue-600 text-white' 
                              : 'bg-green-600 text-white'
                          }`}>
                            {message.role === 'user' ? 'Y' : 'G'}
                          </div>
                          <span className={`font-medium text-xs md:text-sm ${
                            message.role === 'user' ? 'text-blue-300' : 'text-green-300'
                          }`}>
                            {message.role === 'user' ? 'You' : 'Gamani'}
                          </span>
                          <span className="text-xs text-gray-400 opacity-0 group-hover:opacity-100 transition-opacity hidden md:inline">
                            {new Date(message.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                          </span>
                        </div>
                        
                        {/* Message Content */}
                        <div className={`rounded-2xl px-3 py-2.5 md:px-4 md:py-3 ${
                          message.role === 'user' 
                            ? 'bg-blue-600 text-white shadow-lg' 
                            : 'bg-gray-700 text-gray-100 shadow-lg border border-gray-600'
                        }`}>
                          <div className="text-sm leading-relaxed">
                            <p className="break-words whitespace-pre-wrap">
                              {message.content}
                            </p>
                            {message.gameCode && (
                              <div className="mt-2 md:mt-3 px-2.5 md:px-3 py-1.5 md:py-2 bg-green-500/20 border border-green-500/30 rounded-lg">
                                <div className="flex items-center gap-2">
                                  <span className="text-base md:text-lg">🎮</span>
                                  <span className="text-xs md:text-sm font-medium text-green-300">Game Generated</span>
                                </div>
                                <p className="text-xs text-green-200 mt-1 opacity-80">
                                  <span className="hidden md:inline">Check the left panel to play your new game!</span>
                                  <span className="md:hidden">Tap Preview to play!</span>
                                </p>
                              </div>
                            )}
                          </div>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              ) : (
                <div className="flex items-center justify-center h-full">
                  <div className="text-center space-y-4">
                    <div className="w-16 h-16 bg-gradient-to-br from-blue-500 to-green-500 rounded-full mx-auto flex items-center justify-center">
                      <span className="text-2xl">🎮</span>
                    </div>
                    <div>
                      <h3 className="text-lg font-medium text-gray-300 mb-2">Welcome to Gamani!</h3>
                      <p className="text-gray-400 text-sm max-w-md">
                        Start a conversation! Ask me to create games, modify existing ones, or just chat about anything you'd like.
                      </p>
                      <div className="mt-4 space-y-2 text-xs text-gray-500">
                        <p>• "Create a puzzle game"</p>
                        <p>• "Make the background blue"</p>
                        <p>• "What games can you create?"</p>
                      </div>
                    </div>
                  </div>
                </div>
              )}

              {/* Loading indicator for generation */}
              {isGenerating && (
                <div className="flex justify-start group">
                  <div className="max-w-[85%]">
                    {/* Avatar and Name */}
                    <div className="flex items-center gap-2 mb-2">
                      <div className="w-6 h-6 rounded-full bg-green-600 text-white flex items-center justify-center text-xs font-bold">
                        G
                      </div>
                      <span className="font-medium text-sm text-green-300">
                        Gamani
                      </span>
                    </div>
                    
                    {/* Typing Indicator */}
                    <div className="bg-gray-700 shadow-lg border border-gray-600 rounded-2xl px-4 py-3">
                      <div className="flex items-center gap-3">
                        <div className="flex gap-1">
                          <div className="w-2 h-2 bg-blue-400 rounded-full animate-bounce" style={{ animationDelay: '0ms' }}></div>
                          <div className="w-2 h-2 bg-blue-400 rounded-full animate-bounce" style={{ animationDelay: '150ms' }}></div>
                          <div className="w-2 h-2 bg-blue-400 rounded-full animate-bounce" style={{ animationDelay: '300ms' }}></div>
                        </div>
                        <p className="text-gray-300 text-sm">
                          Thinking...
                        </p>
                      </div>
                    </div>
                  </div>
                </div>
              )}
              
              {/* Scroll anchor */}
              <div ref={messagesEndRef} />
            </div>
          </div>
          
          {/* Input area - Fixed at bottom */}
          <div className="p-3 md:p-4 border-t border-gray-700 bg-gray-800">
            <div className="max-w-4xl mx-auto">
              <div className="relative">
                <textarea
                  value={gamePrompt}
                  onChange={(e) => {
                    if (e.target.value.length <= 2000) {
                      setGamePrompt(e.target.value);
                    }
                  }}
                  onKeyDown={handleKeyDown}
                  placeholder={
                    projectStore.currentProject 
                      ? "Message Gamani... (try 'create a puzzle game' or 'what can you do?')"
                      : "Please select a project first to start chatting..."
                  }
                  className="w-full p-3 md:p-4 pr-12 md:pr-16 bg-gray-700 border border-gray-600 rounded-2xl resize-none focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent placeholder-gray-400 shadow-lg text-sm md:text-base"
                  rows={gamePrompt.split('\n').length > 3 ? Math.min(gamePrompt.split('\n').length, 4) : 2}
                  style={{ maxHeight: '100px' }}
                  disabled={isGenerating || !projectStore.currentProject}
                  maxLength={2000}
                />
                <button
                  onClick={handleConversation}
                  disabled={isGenerating || !gamePrompt.trim() || !projectStore.currentProject}
                  className="absolute right-2 bottom-2 w-8 h-8 md:w-10 md:h-10 bg-blue-600 hover:bg-blue-700 disabled:bg-gray-600 disabled:cursor-not-allowed rounded-xl transition-all duration-200 flex items-center justify-center shadow-lg hover:shadow-xl disabled:opacity-50 touch-manipulation"
                  title={isGenerating ? 'Thinking...' : 'Send message'}
                >
                  {isGenerating ? (
                    <div className="w-4 h-4 md:w-5 md:h-5 border-2 border-white border-t-transparent rounded-full animate-spin"></div>
                  ) : (
                    <svg className="w-4 h-4 md:w-5 md:h-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 19l9 2-9-18-9 18 9-2zm0 0v-8" />
                    </svg>
                  )}
                </button>
              </div>
              <div className="flex justify-between items-center mt-2 px-1">
                <div className="text-xs text-gray-500">
                  <span className="hidden sm:inline">Press Enter to send, Shift+Enter for new line</span>
                  <span className="sm:hidden">Enter to send</span>
                </div>
                <div className="text-xs text-gray-500">
                  {gamePrompt.length}/2000
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
      
      {/* Mobile Game Preview Modal/Bottom Sheet */}
      {(showGameModal || (activePanel === 'preview' && generatedGame)) && (
        <div className="md:hidden fixed inset-0 bg-black bg-opacity-50 z-50 touch-manipulation">
          <div className="absolute bottom-0 left-0 right-0 bg-gray-900 rounded-t-xl max-h-[85vh] flex flex-col shadow-2xl">
            {/* Modal handle for swipe indication */}
            <div className="w-12 h-1 bg-gray-600 rounded-full mx-auto mt-2 mb-2"></div>
            
            <div className="p-4 border-b border-gray-700 flex justify-between items-center">
              <h3 className="text-lg font-semibold flex items-center gap-2">
                🎮 Your Game
              </h3>
              <div className="flex gap-2 items-center">
                <button
                  onClick={openGameFullScreen}
                  className="px-3 py-2 text-sm bg-blue-600 hover:bg-blue-700 rounded-lg transition-colors touch-manipulation"
                  title="Open in new tab"
                >
                  <span className="text-lg">⛶</span>
                </button>
                <button
                  onClick={shareGame}
                  disabled={isSharing}
                  className="px-3 py-2 text-sm bg-green-600 hover:bg-green-700 disabled:bg-gray-600 disabled:cursor-not-allowed rounded-lg transition-colors touch-manipulation"
                >
                  {isSharing ? '📤...' : '📤 Share'}
                </button>
                <button
                  onClick={() => {
                    setShowGameModal(false);
                    setActivePanel('chat');
                  }}
                  className="p-2 text-gray-400 hover:text-white hover:bg-gray-700 rounded-lg transition-colors touch-manipulation"
                >
                  ✕
                </button>
              </div>
            </div>
            
            {generatedGame ? (
              <div className="flex-1 p-4 min-h-0">
                <iframe
                  srcDoc={generatedGame}
                  className="w-full h-full border border-gray-600 rounded-lg bg-white"
                  sandbox="allow-scripts allow-same-origin"
                  title="Generated Game"
                />
              </div>
            ) : (
              <div className="flex-1 p-4 flex items-center justify-center">
                <div className="text-center text-gray-400">
                  <div className="w-16 h-16 bg-gray-700 rounded-lg mx-auto mb-4 flex items-center justify-center">
                    <span className="text-2xl">🎮</span>
                  </div>
                  <p>No game generated yet</p>
                  <p className="text-sm mt-2">Create a game in the chat to see it here!</p>
                </div>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
});

export default DashboardPage;