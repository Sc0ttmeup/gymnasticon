#!/usr/bin/env node
"use strict";

var _yargs = _interopRequireDefault(require("yargs"));

var _app = require("./app");

var _cliOptions = require("./cli-options");

var _package = require("../../package.json");

function _interopRequireDefault(obj) { return obj && obj.__esModule ? obj : { default: obj }; }

const banner = String.raw`
   __o
 _ \<_
(_)/(_)

Gymnasticon
v${_package.version}
`;

const argv = _yargs.default.usage(`${banner}\nusage: gymnasticon [OPTIONS]`).config().options(_cliOptions.options).help().version().alias('h', 'help').argv;

(async () => {
  const app = new _app.App(argv);
  await app.run();
