const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const test = require("node:test");

const qml = fs.readFileSync(path.join(__dirname, "../MediaService.qml"), "utf8");
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
  return controller({ Model, artUrl:"https://i.scdn.co/image/fixture",
    remoteArt:true, networkReady:false, artProbed:"", artFile:"", artDominant:"", artLuma:0, artSettling:false,
    artProbe:{running:false,pending:""}, artProbeDelay:timer(),artRetry:timer(),settleCap:timer(),artRetries:0,
  }, ["probeArt", "forgetArt", "applyArtProbe", "finishAttempt", "artFor", "request"]);
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
test("a failed fetch for the new track never leaves the previous cover showing", () => {
  const c=fixture();c.networkReady=true;
  c.applyArtProbe(c.artUrl,"MEAN 445566\nART /tmp/a.png");
  const first=c.artUrl;assert.equal(c.artFor(first),true);
  c.request("https://i.scdn.co/image/next");
  // While the next cover settles, the old one may cross-fade out...
  assert.equal(c.artSettling,true);assert.equal(c.artFor(c.artUrl),true);assert.equal(c.settleCap.running,true);
  // ...but a failure (404, timeout, unsupported format) drops it at once.
  c.finishAttempt(c.artUrl,1);
  assert.equal(c.artFor(c.artUrl),false);assert.equal(c.artFile,"");assert.equal(c.artDominant,"");
});
test("unreadable probe output clears the cover instead of keeping the old one", () => {
  const c=fixture();c.applyArtProbe(c.artUrl,"MEAN 445566\nART /tmp/a.png");
  c.request("file:///tmp/next.png");c.applyArtProbe(c.artUrl,"nothing useful");
  assert.equal(c.artFor(c.artUrl),false);assert.equal(c.artFile,"");
});
test("a successful probe for an older URL does not clear the current one", () => {
  const c=fixture();c.applyArtProbe(c.artUrl,"MEAN 445566\nART /tmp/a.png");
  c.finishAttempt("https://i.scdn.co/image/older",1);assert.equal(c.artFile,"/tmp/a.png");
  c.finishAttempt(c.artUrl,1);assert.equal(c.artFile,"/tmp/a.png");
});
test("requesting the same URL again is a no-op (every bar may ask)", () => {
  const c=fixture();c.request(c.artUrl);assert.equal(c.artProbeDelay.starts,0);
  c.request("file:///tmp/x.png");c.request("file:///tmp/x.png");assert.equal(c.artProbeDelay.starts,1);
});
