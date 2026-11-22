import { buildOptions } from '../lib/options.js';
import { makeIteration } from '../lib/run.js';

export const options = buildOptions('average');
export default makeIteration('average');
