const ChartTooltip = {
  mounted() {
    let tooltip = document.getElementById("chart-floating-tooltip");
    if (!tooltip) {
      tooltip = document.createElement("div");
      tooltip.id = "chart-floating-tooltip";
      tooltip.className =
        "fixed z-50 pointer-events-none hidden px-3 py-2 text-xs rounded-lg shadow-xl font-mono whitespace-pre bg-neutral text-neutral-content border border-base-300 transition-opacity duration-100";
      document.body.appendChild(tooltip);
    }

    this.onPointerOver = (e) => {
      const target = e.target.closest("rect, circle");
      if (!target) return;

      const titleEl = target.querySelector("title");
      if (titleEl) {
        if (!target.getAttribute("data-title")) {
          target.setAttribute("data-title", titleEl.textContent);
        }
        titleEl.remove();
      }

      const titleText = target.getAttribute("data-title");
      if (!titleText || !titleText.trim()) return;

      tooltip.textContent = titleText;
      tooltip.classList.remove("hidden");
      target.style.cursor = "pointer";
      target.style.opacity = "0.8";
    };


    this.onPointerMove = (e) => {
      if (tooltip.classList.contains("hidden")) return;
      const x = Math.min(e.clientX + 14, window.innerWidth - tooltip.offsetWidth - 16);
      const y = Math.min(e.clientY + 14, window.innerHeight - tooltip.offsetHeight - 16);
      tooltip.style.left = `${x}px`;
      tooltip.style.top = `${y}px`;
    };

    this.onPointerOut = (e) => {
      const target = e.target.closest("rect, circle");
      if (target) {
        target.style.opacity = "";
        target.style.cursor = "";
      }
      tooltip.classList.add("hidden");
    };

    this.el.addEventListener("pointerover", this.onPointerOver);
    this.el.addEventListener("pointermove", this.onPointerMove);
    this.el.addEventListener("pointerout", this.onPointerOut);
  },

  destroyed() {
    this.el.removeEventListener("pointerover", this.onPointerOver);
    this.el.removeEventListener("pointermove", this.onPointerMove);
    this.el.removeEventListener("pointerout", this.onPointerOut);
  },
};

export default ChartTooltip;
