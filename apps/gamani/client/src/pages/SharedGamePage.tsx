import { useState, useEffect } from 'react';
import { useParams } from 'react-router-dom';

type SharedGame = {
  shareId: string;
  title: string;
  content: string;
  description: string;
  createdAt: string;
  accessCount: number;
};

const SharedGamePage = () => {
  const { shareId } = useParams<{ shareId: string }>();
  const [game, setGame] = useState<SharedGame | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const fetchSharedGame = async () => {
      if (!shareId) {
        setError('No share ID provided');
        setLoading(false);
        return;
      }

      try {
        const response = await fetch(`/api/games/${shareId}`);

        if (!response.ok) {
          if (response.status === 404) {
            setError('Game not found');
          } else {
            setError('Failed to load game');
          }
          setLoading(false);
          return;
        }

        const result = await response.json();
        
        if (result.success) {
          setGame(result.data);
        } else {
          setError(result.error || 'Failed to load game');
        }
      } catch (error) {
        console.error('Failed to fetch shared game:', error);
        setError('Failed to load game');
      } finally {
        setLoading(false);
      }
    };

    fetchSharedGame();
  }, [shareId]);

  if (loading) {
    return (
      <div className="min-h-screen bg-gray-900 text-white flex items-center justify-center">
        <div className="text-center">
          <div className="animate-spin w-8 h-8 border-4 border-blue-500 border-t-transparent rounded-full mx-auto mb-4"></div>
          <p className="text-gray-400">Loading game...</p>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="min-h-screen bg-gray-900 text-white flex items-center justify-center">
        <div className="text-center">
          <div className="w-16 h-16 bg-red-600 rounded-full mx-auto mb-4 flex items-center justify-center">
            <svg className="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </div>
          <h1 className="text-xl font-bold mb-2">Game Not Found</h1>
          <p className="text-gray-400 mb-4">{error}</p>
          <a 
            href="/" 
            className="px-4 py-2 bg-blue-600 hover:bg-blue-700 rounded transition-colors"
          >
            Go to Gamani
          </a>
        </div>
      </div>
    );
  }

  if (!game) {
    return (
      <div className="min-h-screen bg-gray-900 text-white flex items-center justify-center">
        <div className="text-center">
          <p className="text-gray-400">No game data</p>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gray-900 text-white">
      {/* Header */}
      <div className="bg-gray-800 border-b border-gray-700 px-4 py-3">
        <div className="flex justify-between items-center">
          <div>
            <h1 className="text-xl font-bold">🎮 {game.title}</h1>
            {game.description && (
              <p className="text-sm text-gray-400 mt-1">{game.description}</p>
            )}
          </div>
          <div className="text-right">
            <a 
              href="/" 
              className="px-4 py-2 bg-blue-600 hover:bg-blue-700 rounded transition-colors text-sm"
            >
              Create Your Own Game
            </a>
          </div>
        </div>
      </div>

      {/* Game Info */}
      <div className="bg-gray-800 border-b border-gray-700 px-4 py-2">
        <div className="flex justify-between items-center text-sm text-gray-400">
          <span>Created: {new Date(game.createdAt).toLocaleString()}</span>
          <span>Views: {game.accessCount}</span>
        </div>
      </div>

      {/* Game Content */}
      <div className="p-4 h-[calc(100vh-120px)]">
        <iframe
          srcDoc={game.content}
          className="w-full h-full border border-gray-600 rounded-lg bg-white"
          sandbox="allow-scripts allow-same-origin"
          title={game.title}
        />
      </div>

      {/* Footer */}
      <div className="bg-gray-800 border-t border-gray-700 px-4 py-3 text-center">
        <p className="text-sm text-gray-400">
          Powered by{' '}
          <a href="/" className="text-blue-400 hover:text-blue-300 transition-colors">
            Gamani - AI Game Creator
          </a>
        </p>
      </div>
    </div>
  );
};

export default SharedGamePage;