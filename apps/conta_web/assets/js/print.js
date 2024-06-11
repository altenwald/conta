document.addEventListener("DOMContentLoaded", () => {
  const $print = document.getElementById("window-print");
  if ($print) {
    $print.addEventListener("click", () => {
      window.print();
    });
  }

  const $close = document.getElementById("window-close");
  if ($close) {
    $close.addEventListener("click", () => {
      window.close();
    });
  }
});
