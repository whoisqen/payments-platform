import { buildOptions } from '../lib/options.js';
import { makeIteration } from '../lib/run.js';

export const options = buildOptions('sale-peak');
export default makeIteration('sale-peak');
