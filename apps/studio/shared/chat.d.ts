import * as Y from 'yjs';
import type { AiConversationTurn } from './ai-conversation';
import type { EditProposal } from './ai';
import type { Selection } from './model';
export declare const CHAT_ORIGIN = "poietra-chat";
export declare const CHAT_MAX_MESSAGES = 300;
export interface ChatScope {
    sceneId: string;
    selection: Selection;
    selectedIds: string[];
    label: string;
}
export interface ChatMessage {
    id: string;
    role: 'user' | 'assistant';
    content: string;
    scope: ChatScope;
    authorId: string;
    authorName: string;
    color: string;
    createdAt: number;
    mentionsCodex?: boolean;
    replyTo?: string;
    requestClientId?: number;
    status?: 'pending' | 'complete' | 'failed' | 'cancelled';
    proposal?: EditProposal;
    applied?: boolean;
    dismissed?: boolean;
}
export declare const codexPrompt: (text: string) => string | null;
export declare const chatHistory: (messages: readonly ChatMessage[], sceneId: string, authorId: string) => AiConversationTurn[];
export interface RoomChat {
    readonly doc: Y.Doc;
    snapshot(): ChatMessage[];
    subscribe(listener: () => void): () => void;
    append(message: ChatMessage): void;
    patch(id: string, patch: Partial<Pick<ChatMessage, 'status' | 'applied' | 'dismissed'>>): void;
}
export declare const RoomChat: {
    new (doc: Y.Doc): RoomChat;
};
