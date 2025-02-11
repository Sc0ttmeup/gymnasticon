// File: ant/index.js
// Folder: /ant

import Ant from 'gd-ant-plus';
import { Timer } from '../../util/timer';

const debuglog = require('debug')('gym:servers:ant');

// ANT+ Constants
const DEVICE_TYPE = 0x0b;  // Power meter
const DEVICE_NUMBER = 1;
const PERIOD = 8182;  // 8182/32768 ~4Hz
const RF_CHANNEL = 57;  // 2457 MHz
const BROADCAST_INTERVAL = PERIOD / 32768;  // seconds
const SPEED_CADENCE_DEVICE_TYPE = 0x7D;  // Standard ANT+ Speed & Cadence sensor
const SPEED_CADENCE_CHANNEL = 2;  // Separate channel from power meter
const SPEED_CADENCE_PERIOD = 8070;  // 4Hz transmission rate matching BLE

const defaults = {
  deviceId: 11234,
  channel: 1,
};

export class AntServer {
  constructor(antStick, options = {}) {
    const opts = { ...defaults, ...options };
    this.stick = antStick;
    this.deviceId = opts.deviceId;
    
    // Channel configuration
    this.powerChannel = opts.channel;
    this.speedCadenceChannel = SPEED_CADENCE_CHANNEL;
    
    // Power metrics
    this.eventCount = 0;
    this.accumulatedPower = 0;
    this.power = 0;
    
    // Speed/Cadence metrics
    this.cadence = 0;
    this.crankRevolutions = 0;
    this.crankEventTime = 0;
    this.lastCrankEventTime = 0;
    this.lastUpdateTime = 0;
    
    // Broadcast timer initialization (both channels broadcast at the same interval)
    this.broadcastInterval = new Timer(BROADCAST_INTERVAL);
    this.broadcastInterval.on('timeout', () => {
      this.onPowerBroadcast();
      this.onSpeedCadenceBroadcast();
    });
    
    this._isRunning = false;
  }

  get isRunning() {
    return this._isRunning;
  }

  start() {
    debuglog(`ANT+ server starting [deviceId=${this.deviceId}]`);
    
    // Initialize power channel
    const powerMessages = [
      Ant.Messages.assignChannel(this.powerChannel, 'transmit'),
      Ant.Messages.setDevice(this.powerChannel, this.deviceId, DEVICE_TYPE, DEVICE_NUMBER),
      Ant.Messages.setFrequency(this.powerChannel, RF_CHANNEL),
      Ant.Messages.setPeriod(this.powerChannel, PERIOD),
      Ant.Messages.openChannel(this.powerChannel)
    ];
    
    // Initialize speed/cadence channel
    const speedCadenceMessages = [
      Ant.Messages.assignChannel(this.speedCadenceChannel, 'transmit'),
      // Use deviceId + 1 to avoid conflict with the power channel
      Ant.Messages.setDevice(this.speedCadenceChannel, this.deviceId + 1, SPEED_CADENCE_DEVICE_TYPE, 1),
      Ant.Messages.setFrequency(this.speedCadenceChannel, RF_CHANNEL),
      Ant.Messages.setPeriod(this.speedCadenceChannel, SPEED_CADENCE_PERIOD),
      Ant.Messages.openChannel(this.speedCadenceChannel)
    ];
    
    // Send all initialization messages
    [...powerMessages, ...speedCadenceMessages].forEach(msg => {
      debuglog(`Sending ANT+ message: ${msg.toString('hex')}`);
      this.stick.write(msg);
    });
    
    this.broadcastInterval.reset();
    this._isRunning = true;
    debuglog('ANT+ server started successfully');
  }

  stop() {
    debuglog('Stopping ANT+ server');
    this.broadcastInterval.cancel();
    
    // Close both channels
    [this.powerChannel, this.speedCadenceChannel].forEach(channel => {
      this.stick.write(Ant.Messages.closeChannel(channel));
      this.stick.write(Ant.Messages.unassignChannel(channel));
    });
    
    this._isRunning = false;
    debuglog('ANT+ server stopped');
  }

  updateMeasurement({ power, cadence }) {
    const now = Date.now();
    const timeDiff = now - this.lastUpdateTime;
    
    // Update power metrics
    this.power = power;
    this.cadence = cadence;
    
    // Update crank metrics only if cadence is nonzero and time has elapsed
    if (cadence > 0 && timeDiff > 0) {
      const crankRevsDiff = (cadence * timeDiff) / 60000;
      this.crankRevolutions += Math.round(crankRevsDiff);
      // Convert timeDiff (ms) to ANT ticks (1/1024 sec resolution)
      this.crankEventTime = (this.crankEventTime + timeDiff * 1024 / 1000) & 0xFFFF;
      this.lastCrankEventTime = now;
    }
    
    this.lastUpdateTime = now;
    debuglog(`Updated measurements - Power: ${power}W, Cadence: ${cadence}rpm`);
  }

  onPowerBroadcast() {
    const data = [
      this.powerChannel,
      0x10,               // Data page for power
      this.eventCount,
      0xff,               // Pedal power not used
      this.cadence,
      ...Ant.Messages.intToLEHexArray(this.accumulatedPower, 2),
      ...Ant.Messages.intToLEHexArray(this.power, 2)
    ];
    
    const message = Ant.Messages.broadcastData(data);
    debuglog(`ANT+ power broadcast: power=${this.power}W, cadence=${this.cadence}rpm, accumulated=${this.accumulatedPower}`);
    this.stick.write(message);
    
    this.accumulatedPower = (this.accumulatedPower + this.power) & 0xffff;
    this.eventCount = (this.eventCount + 1) & 0xff;
  }

  onSpeedCadenceBroadcast() {
    // Build payload as per ANT+ Bike Speed/Cadence spec:
    // Byte 0: Data page (0x10)
    // Bytes 1-2: Cumulative Wheel Revolutions (0 if not used)
    // Bytes 3-4: Last Wheel Event Time (0 if not used)
    // Byte 5: Cumulative Crank Revolutions (8-bit)
    // Bytes 6-7: Last Crank Event Time (16-bit LE)
    const data = [
      this.speedCadenceChannel,
      0x10,
      ...Ant.Messages.intToLEHexArray(0, 2), // Wheel Revolutions
      ...Ant.Messages.intToLEHexArray(0, 2), // Wheel Event Time
      this.crankRevolutions & 0xFF,          // Cumulative Crank Revolutions
      ...Ant.Messages.intToLEHexArray(this.crankEventTime, 2)  // Last Crank Event Time
    ];
    
    const message = Ant.Messages.broadcastData(data);
    debuglog(`ANT+ SC broadcast: cranks=${this.crankRevolutions}, eventTime=${this.crankEventTime}`);
    this.stick.write(message);
  }
}
