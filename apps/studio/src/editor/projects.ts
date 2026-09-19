import * as Y from 'yjs';
import { WebsocketProvider } from 'y-websocket';
import * as encoding from 'lib0/encoding';
import * as decoding from 'lib0/decoding';
import * as sync from 'y-protocols/sync';
import type { Project } from '../../shared/model';
import { storeProjectImages } from './images';
import * as moon from '../../../../_build/js/release/build/browser_projects/browser_projects.js';

const runtime = { Y, WebsocketProvider, encoding, decoding, sync, storeProjectImages };
export const createProjectMessages = (source: Y.Doc, project: Project): { updateMessage: Uint8Array; syncMessage: Uint8Array } => moon.createProjectMessages(source, project, runtime);
export const createProjectRoom = (project: Project, signal?: AbortSignal): Promise<URL> => moon.createProjectRoom(project, signal, runtime);
