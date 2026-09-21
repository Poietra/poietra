import { parseArgs } from 'node:util';
import { renderProjectFile, inspectProjectFile } from './index.mjs';
import { readProjectFile, writeResultFile } from './io.mjs';

try {
  const { values, positionals } = parseArgs({ allowPositionals: true, options: {
    format: { type: 'string', default: 'png' }, output: { type: 'string', short: 'o' },
    width: { type: 'string' }, height: { type: 'string' }, fps: { type: 'string' },
    'time-ms': { type: 'string' }, inspect: { type: 'boolean' }, help: { type: 'boolean', short: 'h' },
  } });
  if (values.help) {
    console.log('Usage: node apps/render/cli.mjs INPUT.poietra.json --format png|svg|mp4 -o OUTPUT\n       node apps/render/cli.mjs INPUT.poietra.json --inspect\nOptions: --width N --height N --fps 24|30|60 --time-ms N');
  } else {
    if (positionals.length !== 1 || (!values.inspect && !values.output)) throw new Error('Supply one input file and --output, or use --inspect. See --help.');
    const text = await readProjectFile(positionals[0]);
    if (values.inspect) console.log(JSON.stringify(inspectProjectFile(text), null, 2));
    else {
      const controller = new AbortController();
      const abort = () => controller.abort(new DOMException('Rendering cancelled.', 'AbortError'));
      process.once('SIGINT', abort);
      try {
        const options = { format: values.format, signal: controller.signal };
        for (const [flag, key] of [['width','width'], ['height','height'], ['fps','fps'], ['time-ms','timeMs']]) {
          if (values[flag] !== undefined) options[key] = Number(values[flag]);
        }
        const { bytes, ...metadata } = await renderProjectFile(text, options);
        await writeResultFile(values.output, bytes, controller.signal);
        console.log(JSON.stringify({ output: values.output, bytes: bytes.byteLength, ...metadata }, null, 2));
      } finally { process.off('SIGINT', abort); }
    }
  }
} catch (error) { console.error(error.message ?? error); process.exitCode = 1; }
