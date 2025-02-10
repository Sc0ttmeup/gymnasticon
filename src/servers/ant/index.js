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
    export class AntServer {
      constructor(antStick, options = {}) {
        const opts = {...defaults, ...options};
        this.stick = antStick;
        this.deviceId = opts.deviceId;
    
        // Separate channel tracking
        this.powerChannel = opts.channel;
        this.speedCadenceChannel = SPEED_CADENCE_CHANNEL;
    
        // Power metrics
        this.eventCount = 0;
        this.accumulatedPower = 0;
        this.power = 0;
        this.cadence = 0;
    
        // Speed/Cadence metrics with timestamps
        this.lastUpdateTime = 0;
        this.crankRevolutions = 0;
        this.crankEventTime = 0;
        this.lastCrankEventTime = 0;
    
        // Separate broadcast timers
        this.powerBroadcastInterval = new Timer(BROADCAST_INTERVAL);
        this.speedCadenceBroadcastInterval = new Timer(BROADCAST_INTERVAL);
    
        this.powerBroadcastInterval.on('timeout', this.onPowerBroadcast.bind(this));
        this.speedCadenceBroadcastInterval.on('timeout', this.onSpeedCadenceBroadcast.bind(this));
      }

      get isRunning() {
        return this._isRunning;
      }

      stop() {
        const {stick, powerChannel, speedCadenceChannel} = this;
        this.powerBroadcastInterval.cancel();
        this.speedCadenceBroadcastInterval.cancel();
        const messages = [
          Ant.Messages.closeChannel(powerChannel),
          Ant.Messages.unassignChannel(powerChannel),
          Ant.Messages.closeChannel(speedCadenceChannel),
          Ant.Messages.unassignChannel(speedCadenceChannel),
        ];
        for (let m of messages) {
          stick.write(m);
        }
      }

      updateMeasurement({ power, cadence }) {
        const now = Date.now();
        const timeDiff = now - this.lastUpdateTime;
    
        // Update power metrics
        this.power = power;
        this.cadence = cadence;
    
        // Update crank metrics only if cadence changed
        if (cadence > 0 && timeDiff > 0) {
          const crankRevsDiff = (cadence * timeDiff) / 60000;
          this.crankRevolutions += Math.round(crankRevsDiff);
          this.crankEventTime = (this.crankEventTime + timeDiff * 1024/1000) & 0xFFFF;
          this.lastCrankEventTime = now;
        }
    
        this.lastUpdateTime = now;
      }

      onPowerBroadcast() {
        const data = [
          this.powerChannel,
          0x10,
          this.eventCount,
          0xff,
          this.cadence,
          ...Ant.Messages.intToLEHexArray(this.accumulatedPower, 2),
          ...Ant.Messages.intToLEHexArray(this.power, 2),
        ];
    
        this.stick.write(Ant.Messages.broadcastData(data));
        this.accumulatedPower = (this.accumulatedPower + this.power) & 0xffff;
        this.eventCount = (this.eventCount + 1) & 0xff;
      }

      onSpeedCadenceBroadcast() {
        const data = [
          this.speedCadenceChannel,
          0x10,
          ...Ant.Messages.intToLEHexArray(0, 2), // Wheel Revolutions (0 if not used)
          ...Ant.Messages.intToLEHexArray(0, 2), // Wheel Event Time (0 if not used)
          this.crankRevolutions & 0xFF,          // Cumulative Crank Revolutions (8-bit)
          ...Ant.Messages.intToLEHexArray(this.crankEventTime, 2)  // Last Crank Event Time (16-bit LE)
        ];
        
        const message = Ant.Messages.broadcastData(data);
        debuglog(`ANT+ SC broadcast: cranks=${this.crankRevolutions} time=${this.crankEventTime}`);
        this.stick.write(message);
      }
      
    }
