import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';
import { fileURLToPath } from 'node:url';
import { moonbitClient } from './scripts/moonbit-client.mjs';

export default defineConfig({
  plugins: [moonbitClient(), react(), tailwindcss()],
  // Fonts and generated MoonBit modules are resolved through the workspace root.
  server: { fs: { allow: [fileURLToPath(new URL('../..', import.meta.url))] } },
  build: { target: 'es2022', manifest: true },
  test: { include: ['tests/**/*.test.ts'] },
});
