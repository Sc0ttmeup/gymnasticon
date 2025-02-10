import Ant from 'gd-ant-plus';
import {Timer} from '../../util/timer';

const debuglog = require('debug')('gym:servers:ant');

const DEVICE_TYPE = 0x0b; // power meter
const DEVICE_NUMBER = 1;
const PERIOD = 8182; // 8182/32768 ~4hz
const RF_CHANNEL = 57; // 2457 MHz
const BROADCAST_INTERVAL = PERIOD / 32768; // seconds
const SPEED_CADENCE_DEVICE_TYPE = 0x7D; // Standard ANT+ Speed & Cadence sensor type
const SPEED_CADENCE_CHANNEL = 2; // Separate channel from power meter
const SPEED_CADENCE_PERIOD = 8070; // 4Hz transmission rate matching BLE

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
    
    // Speed/cadence tracking for Keiser
    this.wheelRevolutions = 0;
    this.wheelEventTime = 0;
    this.crankRevolutions = 0;
    this.crankEventTime = 0;
    this.lastCrankRevolutionTime = 0;
    
    this.speedCadenceBroadcastInterval = new Timer(BROADCAST_INTERVAL);
    this.speedCadenceBroadcastInterval.on('timeout', this.onSpeedCadenceBroadcast.bind(this));
  }

  start() {
    const {stick, channel, deviceId} = this;
    const messages = [
      Ant.Messages.assignChannel(channel, 'transmit'),
      Ant.Messages.setDevice(channel, deviceId, DEVICE_TYPE, DEVICE_NUMBER),
      Ant.Messages.setFrequency(channel, RF_CHANNEL),
      Ant.Messages.setPeriod(channel, PERIOD),
      Ant.Messages.openChannel(channel),
    ];
    debuglog(`ANT+ server start [deviceId=${deviceId} channel=${channel}]`);
    for (let m of messages) {
      stick.write(m);
    }
    this.broadcastInterval.reset();

    // Speed/cadence channel setup
    const scMessages = [
      Ant.Messages.assignChannel(SPEED_CADENCE_CHANNEL, 'transmit'),
      Ant.Messages.setDevice(SPEED_CADENCE_CHANNEL, deviceId + 1, SPEED_CADENCE_DEVICE_TYPE, 1),
      Ant.Messages.setFrequency(SPEED_CADENCE_CHANNEL, RF_CHANNEL),
      Ant.Messages.setPeriod(SPEED_CADENCE_CHANNEL, SPEED_CADENCE_PERIOD),
      Ant.Messages.openChannel(SPEED_CADENCE_CHANNEL),
    ];

    for (let m of scMessages) {
      stick.write(m);
    }

    this.speedCadenceBroadcastInterval.reset();
    this._isRunning = true;
  }

  get isRunning() {
    return this._isRunning;
  }

  stop() {
    const {stick, channel} = this;
    this.broadcastInterval.cancel();
    const messages = [
      Ant.Messages.closeChannel(channel),
      Ant.Messages.unassignChannel(channel),
    ];
    for (let m of messages) {
      stick.write(m);
    }
    this.speedCadenceBroadcastInterval.cancel();
    
    // Speed/cadence channel cleanup
    const scMessages = [
      Ant.Messages.closeChannel(SPEED_CADENCE_CHANNEL),
      Ant.Messages.unassignChannel(SPEED_CADENCE_CHANNEL),
    ];
    
    for (let m of scMessages) {
      stick.write(m);
    }
  }

  updateMeasurement({ power, cadence }) {
    this.power = power;
    this.cadence = cadence;
  }

  onBroadcastInterval() {
    const {stick, channel, power, cadence} = this;
    this.accumulatedPower += power;
    this.accumulatedPower &= 0xffff;
    const data = [
      channel,
      0x10, // power only
      this.eventCount,
      0xff, // pedal power not used
      cadence,
      ...Ant.Messages.intToLEHexArray(this.accumulatedPower, 2),
      ...Ant.Messages.intToLEHexArray(power, 2),
    ];
    const message = Ant.Messages.broadcastData(data);
    debuglog(`ANT+ broadcast power=${power}W cadence=${cadence}rpm accumulatedPower=${this.accumulatedPower}W eventCount=${this.eventCount} message=${message.toString('hex')}`);
    stick.write(message);
    this.eventCount++;
    this.eventCount &= 0xff;
  }

  onSpeedCadenceBroadcast() {
    const {stick, cadence} = this;
    
    // Keiser-specific cadence handling
    const now = Date.now();
    if (this.lastCrankRevolutionTime) {
      const timeDiff = now - this.lastCrankRevolutionTime;
      const crankRevsDiff = (cadence * timeDiff) / 60000;
      this.crankRevolutions += Math.round(crankRevsDiff);
      this.crankEventTime = (this.crankEventTime + timeDiff * 1024/1000) & 0xFFFF;
    }
    this.lastCrankRevolutionTime = now;

    const data = [
      SPEED_CADENCE_CHANNEL,
      0x10,
      ...Ant.Messages.intToLEHexArray(this.wheelRevolutions, 2),
      ...Ant.Messages.intToLEHexArray(this.wheelEventTime, 2),
      this.crankRevolutions & 0xFF,
      ...Ant.Messages.intToLEHexArray(this.crankEventTime, 2)
    ];

    const message = Ant.Messages.broadcastData(data);
    debuglog(`ANT+ SC broadcast (Keiser): cranks=${this.crankRevolutions} time=${this.crankEventTime}`);
    stick.write(message);
  }
}
