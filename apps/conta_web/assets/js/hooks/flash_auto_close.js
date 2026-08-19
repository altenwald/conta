const FlashAutoClose = {
  mounted() {
    this.duration = parseInt(this.el.dataset.duration || "3000", 10);
    this.startTimer();

    this.onMouseEnter = () => this.clearTimer();
    this.onMouseLeave = () => this.startTimer();
    this.onTouchStart = () => this.clearTimer();
    this.onTouchEnd = () => this.startTimer();

    this.el.addEventListener("mouseenter", this.onMouseEnter);
    this.el.addEventListener("mouseleave", this.onMouseLeave);
    this.el.addEventListener("touchstart", this.onTouchStart, { passive: true });
    this.el.addEventListener("touchend", this.onTouchEnd, { passive: true });
  },

  updated() {
    this.duration = parseInt(this.el.dataset.duration || "3000", 10);
    this.startTimer();
  },

  destroyed() {
    this.clearTimer();
    this.el.removeEventListener("mouseenter", this.onMouseEnter);
    this.el.removeEventListener("mouseleave", this.onMouseLeave);
    this.el.removeEventListener("touchstart", this.onTouchStart);
    this.el.removeEventListener("touchend", this.onTouchEnd);
  },

  startTimer() {
    this.clearTimer();
    if (this.duration > 0) {
      this.timer = setTimeout(() => {
        this.close();
      }, this.duration);
    }
  },

  clearTimer() {
    if (this.timer) {
      clearTimeout(this.timer);
      this.timer = null;
    }
  },

  close() {
    this.clearTimer();
    this.el.click();
  },
};

export default FlashAutoClose;
