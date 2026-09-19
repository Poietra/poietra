import * as Y from 'yjs';
import { createRoomChat } from '../../../_build/js/release/build/browser_chat/browser_chat.js';
import { codexPrompt as mention, chatHistory as history } from '../../../_build/js/release/build/boundary/boundary.js';
import type { AiConversationTurn } from './ai-conversation';
import type { EditProposal } from './ai';
import type { Selection } from './model';

export const CHAT_ORIGIN = 'poietra-chat';
export const CHAT_MAX_MESSAGES = 300;
export interface ChatScope { sceneId: string; selection: Selection; selectedIds: string[]; label: string }
export interface ChatMessage {
  id: string; role: 'user' | 'assistant'; content: string; scope: ChatScope;
  authorId: string; authorName: string; color: string; createdAt: number;
  mentionsCodex?: boolean; replyTo?: string; requestClientId?: number;
  status?: 'pending' | 'complete' | 'failed' | 'cancelled';
  proposal?: EditProposal; applied?: boolean; dismissed?: boolean;
}

export const codexPrompt: (text: string) => string | null = mention;
export const chatHistory = history as (messages: readonly ChatMessage[], sceneId: string, authorId: string) => AiConversationTurn[];

export interface RoomChat {
  readonly doc: Y.Doc;
  snapshot(): ChatMessage[];
  subscribe(listener: () => void): () => void;
  append(message: ChatMessage): void;
  patch(id: string, patch: Partial<Pick<ChatMessage, 'status' | 'applied' | 'dismissed'>>): void;
}
// Adapt the existing constructor contract to the MoonBit-owned Yjs subscription.
export const RoomChat = function (doc: Y.Doc) { return createRoomChat(doc, Y); } as unknown as { new(doc: Y.Doc): RoomChat };
