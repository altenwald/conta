const CsvFileInput = {
  mounted() {
    this.el.addEventListener("change", (event) => {
      const file = event.target.files[0];
      if (!file) return;

      const target = document.getElementById(this.el.dataset.target);
      if (!target) {
        console.error("CsvFileInput hook: could not find target textarea", this.el.dataset.target);
        return;
      }

      const reader = new FileReader();
      reader.onload = () => {
        target.value = reader.result;
      };
      reader.readAsText(file);
    });
  },
};

export default CsvFileInput;
