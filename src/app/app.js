import noble from '@abandonware/noble';
import bleno from '@abandonware/bleno';
import { once } from 'events';

import { GymnasticonServer } from '../servers/ble';
import { AntServer } from '../servers/ant';
import { createBikeClient, getBikeTypes } from '../bikes';
import { Simulation } from './simulation';
import { Timer } from '../util/timer';
import { Logger } from '../util/logger';
import { createAntStick } from '../util/ant-stick';

const debuglog = require('debug')('gym:app:app');

export { getBikeTypes };

export const defaults = {
  // bike options
  bike: 'autodetect',           // bike type
  bikeReceiveTimeout: 4,        // timeout for receiving stats from bike
  bikeConnectTimeout: 0,        // timeout for establishing bike connection
  bikeAdapter: 'hci0',          // bluetooth adapter to use for bike connection (BlueZ only)

  // flywheel bike options
  flywheelAddress: undefined,   // mac address of bike
  flywheelName: 'Flywheel 1',   // name of bike

  // peloton bike options
  pelotonPath: '/dev/ttyUSB0',  // default path for usb to serial device

  // test bike options
  botPower: 0,                  // power
  botCadence: 0,                // cadence
  botHost: '0.0.0.0',          // listen for udp message to update cadence/power
  botPort: 3000,

  // server options
  serverAdapter: 'hci0',        // adapter for receiving connections from apps
  serverName: 'Gymnasticon2',   // how the Gymnasticon will appear to apps
  serverPingInterval: 1,        // send a power measurement update at least this often

  // ANT+ server options
  antDeviceId: 11234,          // random default ANT+ device id

  // power adjustment (to compensate for inaccurate power measurements on bike)
  powerScale: 1.0,             // multiply power by this
  powerOffset: 0.0,            // add this to power
};

export class App {
  constructor(options = {}) {
    // Bind all callback methods first
    this.onAntStickStartup = this.onAntStickStartup.bind(this);
    this.onSigInt = this.onSigInt.bind(this);
    this.onExit = this.onExit.bind(this);
    this.onPingInterval = this.onPingInterval.bind(this);
    this.onBikeStatsTimeout = this.onBikeStatsTimeout.bind(this);
    this.onBikeConnectTimeout = this.onBikeConnectTimeout.bind(this);
    this.onPedalStroke = this.onPedalStroke.bind(this);
    this.onBikeStats = this.onBikeStats.bind(this);
    this.onBikeDisconnect = this.onBikeDisconnect.bind(this);

    const opts = { ...defaults, ...options };

    this.power = 0;
    this.crank = { revolutions: 0, timestamp: -Infinity };

    // Configure Bluetooth adapters
    process.env['NOBLE_HCI_DEVICE_ID'] = opts.bikeAdapter;
    process.env['BLENO_HCI_DEVICE_ID'] = opts.serverAdapter;
    if (opts.bikeAdapter === opts.serverAdapter) {
      process.env['NOBLE_MULTI_ROLE'] = '1';
    }

    this.opts = opts;
    this.logger = new Logger();
    this.simulation = new Simulation();
    this.server = new GymnasticonServer(bleno, opts.serverName);

    // Initialize ANT+ components
    this.antStick = createAntStick(opts);
    this.antServer = new AntServer(this.antStick, { deviceId: opts.antDeviceId });
    this.antStick.on('startup', this.onAntStickStartup);

    // Setup timers
    this.pingInterval = new Timer(opts.serverPingInterval);
    this.statsTimeout = new Timer(opts.bikeStatsTimeout, { repeats: false });
    this.connectTimeout = new Timer(opts.bikeConnectTimeout, { repeats: false });
    this.powerScale = opts.powerScale;
    this.powerOffset = opts.powerOffset;

    // Connect timer events
    this.pingInterval.on('timeout', this.onPingInterval);
    this.statsTimeout.on('timeout', this.onBikeStatsTimeout);
    this.connectTimeout.on('timeout', this.onBikeConnectTimeout);
    this.simulation.on('pedal', this.onPedalStroke);
  }

  async run() {
    try {
      process.on('SIGINT', this.onSigInt);
      process.on('exit', this.onExit);

      const [state] = await once(noble, 'stateChange');
      if (state !== 'poweredOn') {
        throw new Error(`Bluetooth adapter state: ${state}`);
      }

      this.logger.log('connecting to bike...');
      this.bike = await createBikeClient(this.opts, noble);
      this.bike.on('disconnect', this.onBikeDisconnect);
      this.bike.on('stats', this.onBikeStats);
      
      this.connectTimeout.reset();
      await this.bike.connect();
      this.connectTimeout.cancel();
      
      this.logger.log(`bike connected ${this.bike.address}`);
      await this.server.start();
      this.startAnt();
      
      this.pingInterval.reset();
      this.statsTimeout.reset();
    } catch (e) {
      this.logger.error(e);
      process.exit(1);
    }
  }

  startAnt() {
    if (!this.antStick.is_present()) {
      this.logger.log('no ANT+ stick found');
      return false;
    }
    if (!this.antStick.open()) {
      this.logger.error('failed to open ANT+ stick');
      return false;
    }
    this.logger.log('ANT+ stick found and opened');
    return true;
  }

  onAntStickStartup() {
    this.logger.log('ANT+ stick initialized');
    try {
      this.antServer.start();
      this.logger.log('ANT+ server started successfully');
    } catch (error) {
      this.logger.error(`Failed to start ANT+ server: ${error.message}`);
    }
  }

  onPedalStroke(timestamp) {
    this.pingInterval.reset();
    this.crank.timestamp = timestamp;
    this.crank.revolutions++;
    const { power, crank } = this;
    this.logger.log(`pedal stroke [timestamp=${timestamp} revolutions=${crank.revolutions} power=${power}W]`);
    this.server.updateMeasurement({ power, crank });
  }

  onPingInterval() {
    debuglog(`pinging app since no stats or pedal strokes for ${this.pingInterval.interval}s`);
    const { power, crank } = this;
    this.server.updateMeasurement({ power, crank });
  }

  onBikeStats({ power, cadence }) {
    power = power > 0 ? Math.max(0, Math.round(power * this.powerScale + this.powerOffset)) : 0;
    this.logger.log(`received stats from bike [power=${power}W cadence=${cadence}rpm]`);
    this.statsTimeout.reset();
    this.power = power;
    this.simulation.cadence = cadence;
    const { crank } = this;
    this.server.updateMeasurement({ power, crank });
    this.antServer.updateMeasurement({ power, cadence });
  }

  onBikeStatsTimeout() {
    this.logger.log(`timed out waiting for bike stats after ${this.statsTimeout.interval}s`);
    process.exit(0);
  }

  onBikeDisconnect({ address }) {
    this.logger.log(`bike disconnected ${address}`);
    process.exit(0);
  }

  onBikeConnectTimeout() {
    this.logger.log(`bike connection timed out after ${this.connectTimeout.interval}s`);
    process.exit(1);
  }

  stopAnt() {
    this.logger.log('stopping ANT+ server');
    this.antServer.stop();
  }

  onSigInt() {
    const listeners = process.listeners('SIGINT');
    if (listeners[listeners.length - 1] === this.onSigInt) {
      process.exit(0);
    }
  }

  onExit() {
    if (this.antServer.isRunning) {
      this.stopAnt();
    }
  }
}
