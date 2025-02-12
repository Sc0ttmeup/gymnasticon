import {CyclingPowerService} from './services/cycling-power'
import {CyclingSpeedAndCadenceService} from './services/cycling-speed-and-cadence'
import {BleServer} from '../../util/ble-server'

export const DEFAULT_NAME = 'Gymnasticon2';

/**
 * Handles communication with apps (e.g. Zwift) using the standard Bluetooth
 * LE GATT Cycling Power Service.
 */
export class GymnasticonServer extends BleServer {
	/**
   * Create a GymnasticonServer instance.
   * @param {Bleno} bleno - a Bleno instance.
	 */
  constructor(bleno, name=DEFAULT_NAME) {
    super(bleno, name, [
      new CyclingPowerService(),
      new CyclingSpeedAndCadenceService(),
    ])
  }

  /**
   * Notify subscriber (e.g. Zwift) of new Cycling Power Measurement.
   * @param {object} measurement - new cycling power measurement.
   * @param {number} measurement.power - current power (watts)
	 * @param {object} [measurement.crank] - last crank event.
   * @param {number} measurement.crank.revolutions - revolution count at last crank event.
   * @param {number} measurement.crank.timestamp - timestamp at last crank event.
   */

  // Add error handling to start method
async start() {
  try {
    await super.start();
    debuglog('BLE server started successfully');
  } catch (error) {
    debuglog(`BLE server failed to start: ${error.message}`);
    throw error;
  }
}
  updateMeasurement(measurement) {
    for (let s of this.services) {
      s.updateMeasurement(measurement)
    }
  }
}


