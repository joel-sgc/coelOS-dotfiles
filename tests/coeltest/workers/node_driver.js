// Loads one Node test file with require() and prints what it exports as JSON.
//   node node_driver.js <file.js>
// The test file exports { passed, failed, results: [{name, ok, error?}] } and does not print or exit when required.
// Last line: @@COELTEST@@{json}
const path = require("path");
let res;
try {
  res = require(path.resolve(process.argv[2]));
} catch (e) {
  res = { passed: 0, failed: 1, results: [{ name: "load", ok: false, error: String(e && e.stack || e) }] };
}
console.log("@@COELTEST@@" + JSON.stringify(res));
