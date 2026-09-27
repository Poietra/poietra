import { defineConfig } from '@playwright/test';
import editor from '../../playwright.config';
import { suites } from './suites.ts';
import { report } from './report';

// This suite decodes actual downloads with FFmpeg; ordinary editor shards do not.
export default defineConfig({
  ...editor, testDir: '.', testMatch: suites.mediaEditor,
  workers: 1, fullyParallel: false,
  outputDir: '../../test-results/media-editor', reporter: report('media-editor'),
  webServer: editor.webServer ? { ...editor.webServer, cwd: '../..' } : undefined,
});
