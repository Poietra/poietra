import type { ReactElement } from 'react';
import { ChatThinking as MoonChatThinking } from '../../../../_build/js/release/build/ui/ui.js';
export const ChatThinking = MoonChatThinking as (props: { active: boolean; authorName: string; onStop?: () => void }) => ReactElement;
