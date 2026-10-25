// Fits the card to the sidebar slot (same as the Mac page) and tells the app it can send props.
(function () {
  const cardHeight = 450, cardWidth = 450 * 0.94, margin = 8;
  function fit() {
    const scale = Math.min((innerWidth - margin) / cardWidth, (innerHeight - margin) / cardHeight);
    document.documentElement.style.setProperty('--pc-scale', scale.toFixed(4));
  }
  addEventListener('resize', fit);
  fit();
})();
addEventListener('load', () => requestAnimationFrame(() => requestAnimationFrame(() => window.webkit.messageHandlers.locken.postMessage('ready'))));
