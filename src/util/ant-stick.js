import Ant from 'gd-ant-plus';

const debuglog = require('debug')('gym:util:ant-stick');

/**
 * Create ANT+ stick.
 */
export function createAntStick() {
  let stick = new Ant.GarminStick3; // 0fcf:1009
  
  if (!stick.is_present()) {
    debuglog('GarminStick3 not found, trying GarminStick2');
    stick = new Ant.GarminStick2; // 0fcf:1008
  }

  if (!stick.is_present()) {
    debuglog('No ANT+ stick found');
    throw new Error('No ANT+ stick detected');
  }

  debuglog('ANT+ stick initialized successfully');
  return stick;
}
