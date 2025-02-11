import { Characteristic, Descriptor } from '@abandonware/bleno';

// Flag bits for CSC Measurement:
// Bit 0: Wheel data present
// Bit 1: Crank data present
const FLAG_HASWHEELDATA = 1 << 0;
const FLAG_HASCRANKDATA = 1 << 1;
const CRANK_TIMESTAMP_SCALE = 1024 / 1000; // Conversion factor: seconds -> 1/1024 sec ticks

/**
 * Bluetooth LE GATT CSC Measurement Characteristic implementation.
 * If both wheel and crank data are present, an 8-byte notification is sent.
 * Otherwise, if only crank data is present, a 5-byte notification is sent.
 */
export class CscMeasurementCharacteristic extends Characteristic {
  constructor() {
    super({
      uuid: '2a5b',
      properties: ['notify'],
      descriptors: [
        new Descriptor({
          uuid: '2903',
          value: Buffer.alloc(2)
        })
      ]
    });
  }

  /**
   * Notify subscriber (e.g. Zwift) of new CSC Measurement.
   * The measurement object should contain:
   *   - wheel (optional): { revolutions: number, eventTime: number }
   *   - crank (optional): { revolutions: number, timestamp: number }
   * If both wheel and crank data are present, an 8-byte notification is sent.
   * If only crank data is present, a 5-byte notification is sent.
   */
  updateMeasurement({ wheel, crank }) {
    let flags = 0;
    let value;
    if (wheel && crank &&
        typeof wheel.revolutions === 'number' &&
        typeof wheel.eventTime === 'number' &&
        typeof crank.revolutions === 'number' &&
        typeof crank.timestamp === 'number') {
      // Both wheel and crank data are present.
      flags |= FLAG_HASWHEELDATA;
      flags |= FLAG_HASCRANKDATA;
      value = Buffer.alloc(8);
      value.writeUInt8(flags, 0);
      value.writeUInt16LE(wheel.revolutions & 0xffff, 1);
      value.writeUInt16LE(wheel.eventTime & 0xffff, 3);
      value.writeUInt8(crank.revolutions & 0xff, 5);
      const timestamp16bit = Math.round(crank.timestamp * CRANK_TIMESTAMP_SCALE) & 0xffff;
      value.writeUInt16LE(timestamp16bit, 6);
    } else if (crank &&
               typeof crank.revolutions === 'number' &&
               typeof crank.timestamp === 'number') {
      // Only crank data is available.
      flags |= FLAG_HASCRANKDATA;
      value = Buffer.alloc(5);
      value.writeUInt8(flags, 0);
      value.writeUInt16LE(crank.revolutions & 0xffff, 1);
      const timestamp16bit = Math.round(crank.timestamp * CRANK_TIMESTAMP_SCALE) & 0xffff;
      value.writeUInt16LE(timestamp16bit, 3);
    } else {
      // No data available; send a single byte with flags = 0.
      value = Buffer.alloc(1);
      value.writeUInt8(flags, 0);
    }
    
    if (this.updateValueCallback) {
      this.updateValueCallback(value);
    }
  }
}
