import Ant from 'gd-ant-plus';
import { Timer } from '../../util/timer';

const debuglog = require('debug')('gym:servers:ant');

// ANT+ Constants
const POWER_DEVICE_TYPE = 0x0b;    // Power meter device type
const CSC_DEVICE_TYPE = 0x79;      // Speed & Cadence sensor type
const RF_CHANNEL = 57;             // 2457 MHz
const POWER_PERIOD = 8182;         // ~4Hz (8182/32768)
const CSC_PERIOD = 8182;           // Match power timing
const BROADCAST_INTERVAL = POWER_PERIOD / 32768;  // seconds

// ANT+ network key
const ANT_PLUS_NETWORK_KEY = [0xB9, 0xA5, 0x21, 0xFB, 0xBD, 0x72, 0xC3, 0x45];

const defaults = {
  deviceId: 11234,
  channel: 1,
};

export class AntServer {
  constructor(antStick, options = {}) {
    const opts = { ...defaults, ...options };
    this.stick = antStick;
    this.deviceId = opts.deviceId;
    
    // Power metrics
    this.powerChannel = opts.channel;
    this.eventCount = 0;
    this.accumulatedPower = 0;
    this.power = 0;
    
    // Speed/Cadence metrics
    this.cscChannel = opts.channel + 1;
    this.cadence = 0;
    this.crankRevolutions = 0;
    this.lastCrankTime = 0;
    this.wheelRevolutions = 0;
    this.lastWheelTime = 0;

    this.broadcastInterval = new Timer(BROADCAST_INTERVAL);
    this.broadcastInterval.on('timeout', this.onBroadcastInterval.bind(this));
    this._isRunning = false;
  }

  start() {
    debuglog(`Starting ANT+ server [deviceId=${this.deviceId}]`);

    // Set network key first
    this.stick.write(Ant.Messages.setNetworkKey(0, ANT_PLUS_NETWORK_KEY));

    // Configure Power channel
    const powerMessages = [
      Ant.Messages.assignChannel(this.powerChannel, 'transmit'),
      Ant.Messages.setDevice(this.powerChannel, this.deviceId, POWER_DEVICE_TYPE, 1),
      Ant.Messages.setFrequency(this.powerChannel, RF_CHANNEL),
      Ant.Messages.setPeriod(this.powerChannel, POWER_PERIOD),
      Ant.Messages.openChannel(this.powerChannel)
    ];

    // Configure Speed/Cadence channel
    const cscMessages = [
      Ant.Messages.assignChannel(this.cscChannel, 'transmit'),
      Ant.Messages.setDevice(this.cscChannel, this.deviceId + 1, CSC_DEVICE_TYPE, 1),
      Ant.Messages.setFrequency(this.cscChannel, RF_CHANNEL),
      Ant.Messages.setPeriod(this.cscChannel, CSC_PERIOD),
      Ant.Messages.openChannel(this.cscChannel)
    ];

    // Send all configuration messages
    [...powerMessages, ...cscMessages].forEach(m => {
      debuglog(`Sending ANT+ message: ${m.toString('hex')}`);
      this.stick.write(m);
    });

    this.broadcastInterval.reset();
    this._isRunning = true;
    debuglog('ANT+ server started successfully');
  }

  get isRunning() {
    return this._isRunning;
  }

  stop() {
    debuglog('Stopping ANT+ server');
    this.broadcastInterval.cancel();

    const messages = [
      Ant.Messages.closeChannel(this.powerChannel),
      Ant.Messages.unassignChannel(this.powerChannel),
      Ant.Messages.closeChannel(this.cscChannel),
      Ant.Messages.unassignChannel(this.cscChannel)
    ];

    messages.forEach(m => this.stick.write(m));
    this._isRunning = false;
  }

  updateMeasurement({ power, cadence }) {
    this.power = power;
    this.cadence = cadence;
    
    // Update crank timing based on cadence
    const now = Date.now();
    if (this.cadence > 0) {
      const timeDiff = now - this.lastCrankTime;
      const revsPerMs = this.cadence / 60000;
      this.crankRevolutions += Math.floor(revsPerMs * timeDiff);
    }
    this.lastCrankTime = now;
  }

  onBroadcastInterval() {
    this.broadcastPowerData();
    this.broadcastCSCData();
  }

  broadcastPowerData() {
    this.accumulatedPower = (this.accumulatedPower + this.power) & 0xFFFF;
    
    const data = [
      this.powerChannel,
      0x10,                // Standard power-only data page
      this.eventCount & 0xFF,
      0xFF,               // Pedal power not used
      this.cadence & 0xFF,
      ...Ant.Messages.intToLEHexArray(this.accumulatedPower, 2),
      ...Ant.Messages.intToLEHexArray(this.power, 2)
    ];

    debuglog(`ANT+ power broadcast: power=${this.power}W, cadence=${this.cadence}rpm, accumulated=${this.accumulatedPower}`);
    this.stick.write(Ant.Messages.broadcastData(data));
    this.eventCount = (this.eventCount + 1) & 0xFF;
  }

  broadcastCSCData() {
    const data = [
      this.cscChannel,
      0x10,               // Standard CSC data page
      ...Ant.Messages.intToLEHexArray(this.crankRevolutions & 0xFFFF, 2),
      ...Ant.Messages.intToLEHexArray(this.lastCrankTime & 0xFFFF, 2),
      ...Ant.Messages.intToLEHexArray(this.wheelRevolutions & 0xFFFF, 2),
      ...Ant.Messages.intToLEHexArray(this.lastWheelTime & 0xFFFF, 2)
    ];

    debuglog(`ANT+ CSC broadcast: crankRevs=${this.crankRevolutions}, crankTime=${this.lastCrankTime}`);
    this.stick.write(Ant.Messages.broadcastData(data));
  }
}
