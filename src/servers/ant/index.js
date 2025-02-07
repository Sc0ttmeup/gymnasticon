// File: src/servers/ant/index.js
// ANT server for Gymnasticon using the gd-ant-plus module.
// Revised to use a device type (0x11) allowed by gd-ant-plus and
// to catch errors so that the service does not crash on a rejected message.

import Ant from 'gd-ant-plus';
import { Timer } from '../../util/timer';
import { SpeedCadenceProfile } from './profiles/speed-cadence';

const debuglog = require('debug')('gym:servers:ant');

const DEVICE_TYPE = 0x11; // changed from 0x0b to 0x11 (power meter)
// (If your ANT+ stick actually requires 0x0b, then the gd-ant-plus module may need adjusting.)
const DEVICE_NUMBER = 1;
const PERIOD = 8182; // 8182/32768 ~4hz
const RF_CHANNEL = 57; // 2457 MHz
const BROADCAST_INTERVAL = PERIOD / 32768; // seconds

const defaults = {
  deviceId: 11234,
  channel: 1,
};

/**
 * Handles communication with apps (e.g. Zwift) using the ANT+ Bicycle Power
 * profile (instantaneous cadence and power).
 */
export class AntServer {
  /**
   * Create an AntServer instance.
   * @param {Ant.USBDevice} antStick - ANT+ device instance
   * @param {object} options - configuration options
   * @param {number} options.channel - ANT+ channel
   * @param {number} options.deviceId - ANT+ device id
   */
  constructor(antStick, options = {}) {
    const opts = { ...defaults, ...options };
    this.stick = antStick;
    this.deviceId = opts.deviceId;
    this.eventCount = 0;
    this.accumulatedPower = 0;
    this.channel = opts.channel;

    this.power = 0;
    this.cadence = 0;

    // Initialize the Speed/Cadence profile
    this.speedCadenceProfile = new SpeedCadenceProfile(antStick);
    
    this.broadcastInterval = new Timer(BROADCAST_INTERVAL);
    this.broadcastInterval.on('timeout', this.onBroadcastInterval.bind(this));

    this._isRunning = false;
  }

  /**
   * Start the ANT+ server (set up the channel and start broadcasting).
   */
  start() {
    const { stick, channel, deviceId } = this;
    try {
      const messages = [
        Ant.Messages.assignChannel(channel, 'transmit'),
        Ant.Messages.setDevice(channel, deviceId, DEVICE_TYPE, DEVICE_NUMBER),
        Ant.Messages.setFrequency(channel, RF_CHANNEL),
        Ant.Messages.setPeriod(channel, PERIOD),
        Ant.Messages.openChannel(channel),
      ];
      debuglog(`ANT+ server start [deviceId=${deviceId} channel=${channel}]`);
      for (let m of messages) {
        try {
          stick.write(m);
        } catch (err) {
          debuglog('Error writing message:', err);
        }
      }
    } catch (err) {
      debuglog('Error during ANT+ server start:', err);
    }
    
    // Start the speed/cadence profile
    this.speedCadenceProfile.start();
    
    this.broadcastInterval.reset();
    this._isRunning = true;
  }

  get isRunning() {
    return this._isRunning;
  }

  /**
   * Stop the ANT+ server (stop broadcasting and unassign the channel).
   */
  stop() {
    const { stick, channel } = this;
    this.broadcastInterval.cancel();
    const messages = [
      Ant.Messages.closeChannel(channel),
      Ant.Messages.unassignChannel(channel),
    ];
    for (let m of messages) {
      try {
        stick.write(m);
      } catch (err) {
        debuglog('Error writing message during stop:', err);
      }
    }
    
    // Stop the speed/cadence profile
    this.speedCadenceProfile.stop();
    this._isRunning = false;
  }

  /**
   * Update instantaneous power and cadence.
   * @param {object} measurement - measurement data
   * @param {number} measurement.power - power in watts
   * @param {number} measurement.cadence - cadence in rpm
   */
  updateMeasurement({ power, cadence }) {
    this.power = power;
    this.cadence = cadence;
  }

  /**
   * Broadcast instantaneous power and cadence.
   */
  onBroadcastInterval() {
    const { stick, channel, power, cadence } = this;
    this.accumulatedPower += power;
    this.accumulatedPower &= 0xffff;
    const data = [
      channel,
      0x10, // data page: power only
      this.eventCount,
      0xff, // pedal power not used
      cadence,
      ...Ant.Messages.intToLEHexArray(this.accumulatedPower, 2),
      ...Ant.Messages.intToLEHexArray(power, 2),
    ];
    const message = Ant.Messages.broadcastData(data);
    debuglog(
      `ANT+ broadcast power=${power}W cadence=${cadence}rpm accumulatedPower=${this.accumulatedPower}W eventCount=${this.eventCount} message=${message.toString('hex')}`
    );
    try {
      stick.write(message);
    } catch (err) {
      debuglog('Error broadcasting message:', err);
    }
    
    // Broadcast data for the speed/cadence profile
    const timestamp = process.uptime() * 1000;
    this.speedCadenceProfile.broadcast(this.cadence, timestamp);
    
    this.eventCount++;
    this.eventCount &= 0xff;
  }
}