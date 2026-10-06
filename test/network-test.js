const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const test = require("node:test");

const qml = fs.readFileSync(path.join(__dirname, "../Panel.qml"), "utf8");
function controller(values, functions) {
  const context = vm.createContext(values);
  context.root = context;
  // Exercise the controller's production functions with observable process/timer boundaries.
  for (const name of functions) {
    const start = qml.indexOf("function " + name + "(");
    assert.ok(start >= 0, "Missing controller function: " + name);
    let end = qml.indexOf("{", start) + 1;
    let depth = 1;
    while (depth && end < qml.length) {
      if (qml[end] === "{") depth++;
      if (qml[end] === "}") depth--;
      end++;
    }
    vm.runInContext(qml.slice(start, end), context);
  }
  return context;
}
function timer() {
  return { running: false, interval: 0, starts: 0,
    restart() { this.running = true; this.starts++; },
    stop() { this.running = false; } };
}

const Model = require("../Model.js");
function fixture() {
  return controller({ Model, artWanted:true, artUrl:"https://i.scdn.co/image/fixture",
    remoteArt:true, networkReady:false, artProbed:"", artFile:"", artDominant:"", artMean:"", artLuma:0,
    artProbe:{running:false,pending:""}, artProbeDelay:timer(),artRetry:timer(),artRetries:0,
  }, ["probeArt", "forgetArt", "applyArtProbe"]);
}
test("remote artwork waits, but a local file can load offline", () => {
  const c=fixture();c.probeArt(false);assert.equal(c.artProbe.running,false);
  c.artUrl="file:///tmp/fixture.png";c.remoteArt=false;c.probeArt(false);
  assert.equal(c.artProbe.running,true);assert.equal(c.artProbe.command.at(-1),"/tmp/fixture.png");
});
test("track changes serialize cancellation before starting the replacement", () => {
  const c=fixture();c.networkReady=true;c.artProbe.running=true;c.artProbe.pending="old";
  c.probeArt(false);assert.equal(c.artProbe.running,false);assert.equal(c.artProbe.pending,"old");
  assert.equal(c.artProbeDelay.running,true);assert.equal(c.artProbe.command,undefined);
  c.probeArt(false);assert.equal(c.artProbe.running,true);assert.equal(c.artProbe.pending,c.artUrl);
});
test("successful artwork clears retries; late results cannot replace the current cover", () => {
  const c=fixture();c.artRetries=2;c.artRetry.running=true;
  c.applyArtProbe("old","MEAN 112233\nART /tmp/old.png");assert.equal(c.artFile,"");
  c.applyArtProbe(c.artUrl,"MEAN 445566\nART /tmp/new.png");
  assert.equal(c.artFile,"/tmp/new.png");assert.equal(c.artRetries,0);assert.equal(c.artRetry.running,false);
});
test("disallowed remote hosts still never start a probe", () => {
  const c=fixture();c.networkReady=true;c.artUrl="https://example.invalid/cover.png";
  c.probeArt(false);assert.equal(c.artProbe.running,false);
});
