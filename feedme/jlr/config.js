// Client identity for JLR Environmental's FeedMe Pro build.
// feedme/jlr/ is a fully standalone deployment — its index.html is JLR's
// own independent codebase, not shared with any other client.
window.FMP_CONFIG = {
  clientId: "jlr",
  clientName: "JLR Environmental",
  // Skips the first-run "what's your company name" setup modal — goes
  // straight into the app already branded for JLR.
  _setupComplete: true
};
