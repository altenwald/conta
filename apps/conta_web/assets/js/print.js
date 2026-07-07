document.addEventListener("DOMContentLoaded", () => {
  // The navbar renders its actions slot once for the desktop layout and
  // once inside the mobile dropdown, so these buttons appear more than
  // once in the DOM. Bind by class (querySelectorAll), not by id -
  // getElementById would only ever find the first (possibly hidden) copy.
  document.querySelectorAll(".js-window-print").forEach(($print) => {
    $print.addEventListener("click", () => {
      window.print();
    });
  });

  document.querySelectorAll(".js-window-close").forEach(($close) => {
    $close.addEventListener("click", () => {
      window.close();
    });
  });
});
