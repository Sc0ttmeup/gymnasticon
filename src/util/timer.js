// File: util/timer.js
// Drift-compensated Timer that emits a 'timeout' event after a specified interval.
// This version adjusts for drift by calculating the expected expiration time 
// and then compensating in the delay for subsequent timeouts.

import { EventEmitter } from 'events';

export class Timer extends EventEmitter {
  /**
   * Create a Timer instance.
   * @param {number} interval - time until expires in seconds.
   * @param {object} options
   * @param {boolean} [options.repeats=true] - restart the timer each time it expires.
   */
  constructor(interval, { repeats = true } = {}) {
    super();
    this._interval = interval; // in seconds
    this._repeats = repeats;
    this._timeout = null;
    this._expected = 0; // expected timestamp (in ms) for next expiration
    this.onExpire = this.onExpire.bind(this);
  }

  /**
   * Get the current interval (seconds).
   */
  get interval() {
    return this._interval;
  }

  /**
   * Reset the timer with drift compensation.
   */
  reset() {
    this.clearTimeout();
    // Set the expected expiration time based on the current time.
    this._expected = Date.now() + this._interval * 1000;
    if (Number.isFinite(this._interval) && this._interval > 0) {
      this._timeout = setTimeout(this.onExpire, this._interval * 1000);
    }
  }

  /**
   * Cancel the timer.
   */
  cancel() {
    this.clearTimeout();
  }

  /**
   * Handle timer expiry.
   * Emits a 'timeout' event with the interval.
   * @private
   */
  onExpire() {
    const now = Date.now();
    // Calculate drift: the difference between now and the expected expiration.
    const drift = now - this._expected;
    this.emit('timeout', this._interval);
    if (this._repeats) {
      // Increment expected expiration by the interval.
      this._expected += this._interval * 1000;
      // Calculate the next delay, compensating for drift.
      const nextDelay = Math.max(0, this._interval * 1000 - drift);
      this._timeout = setTimeout(this.onExpire, nextDelay);
    }
  }

  /**
   * Clear the internal timeout.
   * @private
   */
  clearTimeout() {
    if (this._timeout) {
      clearTimeout(this._timeout);
      this._timeout = null;
    }
  }
}
