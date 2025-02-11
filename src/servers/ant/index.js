#!/usr/bin/env node
// File: ant/index.js
// Folder: /ant
//
// This file implements the ANT+ server for Gymnasticon.
// It opens two channels – one for power and one for speed/cadence.
// It simulates wheel data (defaulting to about 1 revolution per second)
// and uses cadence to compute crank (cadence) data.

import Ant from 'gd-ant-plus';
import { Timer } from '../../util/timer';

const debuglog = require('debug')('gym:servers:ant');

// ANT+ Constants
const DEVICE_TYPE = 0x0b;            // Power meter device type
const DEVICE_NUMBER = 1;
const PERIOD = 8182;               // ~4Hz (8182/32768)
const RF_CHANNEL = 57;             // 2457 MHz
const BROADCAST_INTERVAL = PERIOD / 32768;  // seconds (~0.25 s)
const SPEED_CADENCE_DEVICE_TYPE = 0x7D;  // Standard ANT+ Speed & Cadence sensor type
const SPEED_CADENCE_CHANNEL = 2;         // Separate channel from power meter
const SPEED_CADENCE_PERIOD = 8070;         // ~4Hz transmission matching BLE

// Default options
const defaults = {
  deviceId: 11236,  // Power channel device ID; speed/cadence uses deviceId+1.
  channel: 1,
};
  // Add constant for ANT+ network key
  const ANT_PLUS_NETWORK_KEY = [0xB9, 0xA5, 0x21, 0xFB, 0xBD, 0x72, 0xC3, 0x45];

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
    
      // Speed/Cadence metrics (for crank data)
      this.cadence = 0;
      this.crankRevolutions = 0;
      this.crankEventTime = 0;
    
      // Simulated wheel data for speed
      this.simulatedWheelFraction = 0;
      this.wheelRevolutions = 0;
      this.wheelEventTime = 0;
    
      this.lastUpdateTime = Date.now();
    
      // Broadcast timer: every ~250ms broadcast power and speed/cadence messages.
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
      async start() {
        debuglog(`ANT+ server starting [deviceId=${this.deviceId}]`);
    
        // Set network key first
        const networkKeyMessage = Ant.Messages.setNetworkKey(0, ANT_PLUS_NETWORK_KEY);
        this.stick.write(networkKeyMessage);
      
        // Wait for network key acknowledgment
        await new Promise(resolve => setTimeout(resolve, 500));
      
        // Then configure channels
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
          // Use deviceId+1 to avoid conflict with the power channel
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

  /**
   * Update measurement from the bike.
   * Expected properties:
   *   power: number (watts)
   *   cadence: number (rpm)
   *
   * This implementation calculates crank data from cadence if available.
   */
  updateMeasurement({ power, cadence }) {
    const now = Date.now();
    this.power = power;
    this.cadence = cadence;
    
    // Calculate crank data from cadence.
    const timeDiff = now - this.lastUpdateTime;
    if (cadence > 0 && timeDiff > 0) {
      const revsPerMs = cadence / 60000;  // revolutions per millisecond
      const revsDiff = revsPerMs * timeDiff;
      // Update cumulative crank revolutions (8-bit wrap-around)
      this.crankRevolutions = (this.crankRevolutions + Math.round(revsDiff)) & 0xFF;
      // Update crank event time (1024 ticks per second)
      this.crankEventTime = (this.crankEventTime + (timeDiff * 1024 / 1000)) & 0xFFFF;
    }
    this.lastUpdateTime = now;
    debuglog(`Updated measurements - Power: ${power}W, Cadence: ${cadence}rpm, Cranks: ${this.crankRevolutions}`);
  }

  onPowerBroadcast() {
    const data = [
      this.powerChannel,
      0x10,               // Data page for power-only message
      this.eventCount,
      0xff,               // Pedal power not used
      this.cadence,
      ...Ant.Messages.intToLEHexArray(this.accumulatedPower, 2),
      ...Ant.Messages.intToLEHexArray(this.power, 2)
    ];
    
    const message = Ant.Messages.broadcastData(data);
    debuglog(`ANT+ power broadcast: power=${this.power}W, cadence=${this.cadence}rpm, accumulated=${this.accumulatedPower}`);
    this.stick.write(message);
    
    this.accumulatedPower = (this.accumulatedPower + this.power) & 0xFFFF;
    this.eventCount = (this.eventCount + 1) & 0xFF;
  }

  onSpeedCadenceBroadcast() {
    // Simulate wheel data: assume 1 revolution per second.
    // With a broadcast interval of ~250ms, add 0.25 revolution per broadcast.
    this.simulatedWheelFraction += 0.25;
    if (this.simulatedWheelFraction >= 1) {
      const revsToAdd = Math.floor(this.simulatedWheelFraction);
      this.wheelRevolutions += revsToAdd;
      this.simulatedWheelFraction -= revsToAdd;
    }
    // Increment wheel event time by ~256 ticks per 250ms update.
    this.wheelEventTime = (this.wheelEventTime + 256) & 0xFFFF;
    
    // Build payload per ANT+ CSC specification:
    // Byte 0: Data page (0x10)
    // Bytes 1-2: Cumulative Wheel Revolutions (uint16, little-endian)
    // Bytes 3-4: Last Wheel Event Time (uint16, little-endian)
    // Byte 5: Cumulative Crank Revolutions (uint8)
    // Bytes 6-7: Last Crank Event Time (uint16, little-endian)
    const data = [
      this.speedCadenceChannel,
      0x10,
      ...Ant.Messages.intToLEHexArray(this.wheelRevolutions, 2),
      ...Ant.Messages.intToLEHexArray(this.wheelEventTime, 2),
      this.crankRevolutions & 0xFF,
      ...Ant.Messages.intToLEHexArray(this.crankEventTime, 2)
    ];
    
    const message = Ant.Messages.broadcastData(data);
    debuglog(`ANT+ SC broadcast: WheelRevs=${this.wheelRevolutions}, WheelTime=${this.wheelEventTime}, CrankRevs=${this.crankRevolutions}, EventTime=${this.crankEventTime}`);
    this.stick.write(message);
  }
}
