import * as Y from "yjs";
import { createRoomChat } from "../../../_build/js/release/build/browser_chat/browser_chat.js";
import { codexPrompt as mention, chatHistory as history } from "../../../_build/js/release/build/boundary/boundary.js";
export const CHAT_ORIGIN = 'poietra-chat';
export const CHAT_MAX_MESSAGES = 300;
export const codexPrompt = mention;
export const chatHistory = history;
// Adapt the existing constructor contract to the MoonBit-owned Yjs subscription.
export const RoomChat = function (doc) { return createRoomChat(doc, Y); };
