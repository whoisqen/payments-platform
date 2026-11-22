import { buildOptions } from '../lib/options.js';
import { makeIteration } from '../lib/run.js';

export const options = buildOptions('smoke');
export default makeIteration('smoke');
