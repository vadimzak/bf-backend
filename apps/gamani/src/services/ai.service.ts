import { getGoogleAI, isGoogleAIInitialized } from '../config/google-ai';
import { AIGenerateRequest } from '../types';
import { createLogger } from '../utils/logger';

const logger = createLogger('GOOGLE AI SERVICE');

export class AIService {
  static async generateResponse(requestData: AIGenerateRequest): Promise<string> {
    const { prompt, conversation, currentGame } = requestData;

    if (!isGoogleAIInitialized()) {
      logger.error('AI service not initialized - this should not happen with fail-fast startup');
      throw new Error('AI service not available. Server may be starting up.');
    }

    const genAI = getGoogleAI();

    let contextualPrompt = '';
    
    if (conversation && conversation.length > 0) {
      contextualPrompt += 'Previous conversation context:\n';
      conversation.forEach((msg, index) => {
        if (index >= conversation.length - 10) {
          contextualPrompt += `${msg.role === 'user' ? 'User' : 'Assistant'}: ${msg.content}\n`;
        }
      });
      contextualPrompt += '\n';
    }

    if (currentGame) {
      contextualPrompt += 'Current game code for reference/modification:\n';
      contextualPrompt += `${currentGame}\n\n`;
    }

    const gamePrompt = `You are Gamani, a friendly AI assistant that specializes in creating children's games. You can have natural conversations and help with game development when requested.

${contextualPrompt}Current user request: "${prompt}"

Guidelines for responses:
- Have natural, engaging conversations with users
- Only create or modify games when the user explicitly requests it (e.g., "create a game", "make a racing game", "change the background color")
- For general questions or conversation, respond naturally without generating games
- When you do create/modify a game, always explain what you're doing in your response

When creating or modifying games:
- Create complete, fun, interactive games suitable for children
- Use English text for all UI elements and instructions
- Make games interactive and engaging with bright colors
- Ensure games work on both desktop and mobile
- Always wrap the HTML code in \`\`\`html code blocks
- Provide a clear explanation of what you created or changed
- Include game instructions in your explanation

Example response format when creating a game:
"I'll create a fun [game type] for you! [Brief explanation of the game]

\`\`\`html
<!DOCTYPE html>
<html>
<!-- Complete game code here -->
</html>
\`\`\`

[Additional explanation of features, how to play, what makes it fun, etc.]"

For conversations that don't involve games, simply respond naturally and helpfully. You can discuss games, programming, or anything else the user is interested in.`;

    const result = await genAI.models.generateContent({
      model: 'gemini-2.5-pro',
      contents: [{
        role: 'user',
        parts: [{ text: gamePrompt }]
      }]
    });
    
    const text = result.text || '';

    logger.success('Generated response with conversation context:', {
      promptLength: prompt.length,
      conversationLength: conversation?.length || 0,
      hasCurrentGame: !!currentGame,
      responseLength: text.length
    });

    return text;
  }
}