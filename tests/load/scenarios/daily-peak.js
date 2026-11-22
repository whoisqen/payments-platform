import { buildOptions } from '../lib/options.js';
import { makeIteration } from '../lib/run.js';

export const options = buildOptions('daily-peak');
export default makeIteration('daily-peak');
