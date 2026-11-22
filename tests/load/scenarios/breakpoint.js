import { buildOptions } from '../lib/options.js';
import { makeIteration } from '../lib/run.js';

export const options = buildOptions('breakpoint');
export default makeIteration('breakpoint');
