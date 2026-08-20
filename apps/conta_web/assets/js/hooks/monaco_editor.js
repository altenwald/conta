const MonacoEditor = {
  mounted() {
    const monaco = window.MonacoEditorLib;

    if (!monaco) {
      console.error(
        "MonacoEditor hook: window.MonacoEditorLib is not available (monaco_bundle.js failed to load or hasn't loaded yet)"
      );
      return;
    }

    const targetId = this.el.dataset.target;
    this.hiddenInput = document.getElementById(targetId);

    if (!this.hiddenInput) {
      console.error("MonacoEditor hook: could not find target input", targetId);
      return;
    }

    const initialValue = this.el.dataset.value || "";
    const dataTheme = document.documentElement.getAttribute("data-theme");
    const isDark = dataTheme
      ? dataTheme === "dark"
      : window.matchMedia("(prefers-color-scheme: dark)").matches;

    this.editor = monaco.editor.create(this.el, {
      value: initialValue,
      language: "lua",
      theme: isDark ? "vs-dark" : "vs",
      automaticLayout: true,
      minimap: { enabled: false },
      scrollBeyondLastLine: true,
    });

    this.lastSyncedValue = initialValue;

    // Keep hidden input value updated in real time so form submissions / test runs
    // always see the exact current code even before blur.
    this.editor.onDidChangeModelContent(() => {
      if (this.hiddenInput) {
        this.hiddenInput.value = this.editor.getValue();
      }
    });

    // On blur, trigger LiveView validation only if the value actually changed
    this.editor.onDidBlurEditorWidget(() => {
      const currentValue = this.editor.getValue();
      if (this.hiddenInput && currentValue !== this.lastSyncedValue) {
        this.lastSyncedValue = currentValue;
        this.hiddenInput.value = currentValue;
        this.hiddenInput.dispatchEvent(new Event("input", { bubbles: true }));
      }
    });

    // Ensure focus is properly claimed on click / mousedown
    this.el.addEventListener("mousedown", () => {
      this.editor.focus();
    });
    this.el.addEventListener("click", () => {
      this.editor.focus();
    });

    // Re-assert focus after LiveView morphdom patches if Monaco was focused
    this.onPhxUpdate = () => {
      if (this.editor?.hasTextFocus()) {
        this.editor.focus();
      }
    };
    document.addEventListener("phx:update", this.onPhxUpdate);

    // Stop ONLY keystroke input and change events from bubbling into LiveView's
    // form phx-change="validate". Allow all focus and selection events to bubble
    // so Monaco's internal document listeners operate normally.
    this.el.addEventListener("input", (e) => e.stopPropagation());
    this.el.addEventListener("change", (e) => e.stopPropagation());

    // Explicit ResizeObserver to immediately update Monaco's layout when the
    // surrounding grid or card size changes (e.g. typing in Description, adding parameters).
    this.resizeObserver = new ResizeObserver(() => {
      window.requestAnimationFrame(() => {
        if (this.editor && this.el) {
          this.editor.layout();
        }
      });
    });
    this.resizeObserver.observe(this.el);

    // Initial layout pass
    window.requestAnimationFrame(() => {
      this.editor?.layout();
    });
  },

  updated() {
    this.hiddenInput = document.getElementById(this.el.dataset.target);

    // Immediate layout refresh on LiveView DOM update
    window.requestAnimationFrame(() => {
      this.editor?.layout();
    });
  },

  destroyed() {
    if (this.onPhxUpdate) {
      document.removeEventListener("phx:update", this.onPhxUpdate);
    }
    this.resizeObserver?.disconnect();
    this.editor?.dispose();
  },
};

export default MonacoEditor;
