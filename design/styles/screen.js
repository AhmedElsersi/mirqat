// Theme from ?theme=dark|light (the gallery sets it), icons, and a mushaf page
// sized the way the app sizes it: the largest text at which every line fits.
(function () {
  const theme = new URLSearchParams(location.search).get('theme');
  if (theme) document.documentElement.dataset.theme = theme;
  if (window.lucide) window.lucide.createIcons();

  function fitPages() {
    document.querySelectorAll('.page').forEach((page) => {
      const lines = [...page.querySelectorAll('.m-line:not(.m-head)')];
      if (!lines.length) return;
      let size = 22;
      page.style.fontSize = size + 'px';
      const over = () => lines.some((l) => l.scrollWidth > l.clientWidth + 0.5);
      while (over() && size > 10) {
        size -= 0.25;
        page.style.fontSize = size + 'px';
      }
    });
  }
  (document.fonts ? document.fonts.ready : Promise.resolve()).then(fitPages);
})();
