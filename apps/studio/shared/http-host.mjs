// Preserve native error identity across independently linked MoonBit entry points.
let uploadError;
export function uploadErrorClass(fields) {
  return uploadError ??= class extends Error {
    constructor(message, ...args) { super(message); Object.assign(this, fields(...args)); }
  };
}
