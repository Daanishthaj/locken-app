// Runs before the page paints: marks that scripts are on, so elements that animate in can start hidden.
// If the main script never starts (blocked or failed), show everything after a moment instead.
document.documentElement.classList.add("js");
setTimeout(function () {
  if (!document.documentElement.classList.contains("site-ready")) document.documentElement.classList.remove("js");
}, 4000);
