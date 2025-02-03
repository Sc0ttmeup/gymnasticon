const Ant = require('ant-plus');

// ANT+ Speed & Cadence Profile (0x79)
const DEVICE_TYPE = 0x79;
const TRANSMISSION_TYPE = 0x05;
const PERIOD = 8102;  // 4.06Hz
const RF_FREQ = 57;   // 2457 MHz
const CHANNEL_TYPE = 0x10;  // Bidirectional transmit channel

export class SpeedCadenceProfile {
  constructor(stick) {
    this.stick = stick;
    this.channel = 0;
  }

  start() {
    const { channel, stick } = this;
    const messages = [
      Ant.Messages.assignChannel(channel, CHANNEL_TYPE),
      Ant.Messages.setChannelId(channel, 0, DEVICE_TYPE, TRANSMISSION_TYPE),
      Ant.Messages.setChannelRfFreq(channel, RF_FREQ),
      Ant.Messages.setChannelPeriod(channel, PERIOD),
      Ant.Messages.openChannel(channel)
    ];
    
    for (let m of messages) {
      stick.write(m);
    }
  }

  stop() {
    const { channel, stick } = this;
    const messages = [
      Ant.Messages.closeChannel(channel),
      Ant.Messages.unassignChannel(channel)
    ];
    
    for (let m of messages) {
      stick.write(m);
    }
  }

  broadcast(cadence, timestamp) {
    const payload = Buffer.alloc(8);
    
    // Page 0 format
    payload[0] = 0;  // Page number
    payload[2] = cadence & 0xFF;  // Cadence event count LSB
    payload[3] = (cadence >> 8) & 0xFF;  // Cadence event count MSB
    payload[4] = timestamp & 0xFF;  // Cadence event time LSB
    payload[5] = (timestamp >> 8) & 0xFF;  // Cadence event time MSB

    this.stick.write(
      Ant.Messages.broadcastData(this.channel, payload)
    );
  }
}
