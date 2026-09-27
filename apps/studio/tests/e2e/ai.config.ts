import { defineConfig } from '@playwright/test';
import { suites } from './suites.ts';
import editorConfig from '../../playwright.config';

export default defineConfig({ ...editorConfig, testDir: '.', testMatch: suites.editor.filter(file => file.startsWith('ai')) });
