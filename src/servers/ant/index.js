import Ant from 'gd-ant-plus';
import {Timer} from '../../util/timer';

const debuglog = require('debug')('gym:servers:ant');

const DEVICE_TYPE = 0x0b; // power meter
const DEVICE_NUMBER = 1;
const PERIOD = 8182; // 8182/32768 ~4hz
const RF_CHANNEL = 57; // 2457 MHz
const BROADCAST_INTERVAL = PERIOD / 32768; // seconds

const defaults = {
  deviceId: 11234,
  channel: 1,
}

export class AntServer {
  constructor(antStick, options = {}) {
    const opts = {...defaults, ...options};
    this.stick = antStick;
    this.deviceId = opts.deviceId;
    this.eventCount = 0;
    this.accumulatedPower = 0;
    this.channel = opts.channel;
    this.power = 0;
    this.cadence = 0;

    this.broadcastInterval = new Timer(BROADCAST_INTERVAL);
    this.broadcastInterval.on('timeout', this.onBroadcastInterval.bind(this));

    this._isRunning = false;
  }

  start() {
    try {
      const {stick, channel, deviceId} = this;
      // Convert values to proper types to avoid type errors
      const messages = [
        Ant.Messages.assignChannel(Number(channel), 'transmit'),
        Ant.Messages.setDevice(Number(channel), Number(deviceId), Number(DEVICE_TYPE), Number(DEVICE_NUMBER)),
        Ant.Messages.setFrequency(Number(channel), Number(RF_CHANNEL)),
        Ant.Messages.setPeriod(Number(channel), Number(PERIOD)),
        Ant.Messages.openChannel(Number(channel))
      ];
      
      debuglog(`ANT+ server start [deviceId=${deviceId} channel=${channel}]`);
      
      for (let m of messages) {
        if (m && stick.write) {
          stick.write(m);
        }
      }
      
      this.broadcastInterval.reset();
      this._isRunning = true;
    } catch (err) {
      debuglog(`Error starting ANT+ server: ${err.message || err}`);
      throw err;
    }
  }

  get isRunning() {
    return this._isRunning;
  }

  stop() {
    const {stick, channel} = this;
    this.broadcastInterval.cancel();
    try {
      const messages = [
        Ant.Messages.closeChannel(Number(channel)),
        Ant.Messages.unassignChannel(Number(channel))
      ];
      
      for (let m of messages) {
        if (m && stick.write) {
          stick.write(m);
        }
      }
      this._isRunning = false;
    } catch (err) {
      debuglog(`Error stopping ANT+ server: ${err.message || err}`);
    }
  }

  updateMeasurement({ power, cadence }) {
    this.power = Number(power) || 0;
    this.cadence = Number(cadence) || 0;
  }

  onBroadcastInterval() {
    try {
      const {stick, channel, power, cadence} = this;
      this.accumulatedPower += power;
      this.accumulatedPower &= 0xffff;
      
      const data = [
        Number(channel),
        0x10, // power only
        this.eventCount,
        0xff, // pedal power not used
        Number(cadence),
        ...Ant.Messages.intToLEHexArray(this.accumulatedPower, 2),
        ...Ant.Messages.intToLEHexArray(power, 2)
      ];
      
      const message = Ant.Messages.broadcastData(data);
      debuglog(`ANT+ broadcast power=${power}W cadence=${cadence}rpm accumulatedPower=${this.accumulatedPower}W eventCount=${this.eventCount} message=${message.toString('hex')}`);
      
      if (message && stick.write) {
        stick.write(message);
      }
      
      this.eventCount++;
      this.eventCount &= 0xff;
    } catch (err) {
      debuglog(`Error in broadcast interval: ${err.message || err}`);
    }
  }
}
