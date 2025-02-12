#!/usr/bin/env node

import yargs from 'yargs';
import {App} from './app';
import {options} from './cli-options';
import {version} from '../../package.json';

const banner = String.raw`
   __o  
 _ \<_  
(_)/(_) 

Gymnasticon
v${version}
`

const argv = yargs
  .usage(`${banner}\nusage: gymnasticon [OPTIONS]`)
  .config()
  .options(options)
  .help()
  .version()
  .alias('h', 'help')
  .argv;
  // Add global error handler
  process.on('unhandledRejection', (error) => {
    console.error('Unhandled promise rejection:', error);
    // Optionally restart the service or exit gracefully
    process.exit(1);
  });

  // Add verbose logging
  const debuglog = require('debug')('gym:app');

  // Wrap main execution in try-catch
  async function main() {
    try {
      const app = new App(argv);
      debuglog('Initializing hardware connections...');
      await app.run();
    } catch (error) {
      debuglog('Detailed error:', {
        name: error.name,
        message: error.message,
        stack: error.stack,
        code: error.code
      });
      process.exit(1);
    }
  }
  main();