(() => {
  const csrf = document.querySelector("meta[name='csrf-token']")?.getAttribute("content");

  const Hooks = {
    WotexChart: {
      mounted() {
        if (!window.vegaEmbed) return;

        let spec;
        try {
          spec = JSON.parse(this.dataset.spec);
        } catch (_error) {
          return;
        }

        const target = document.createElement("div");
        target.className = "wl-chart-enhanced";
        target.setAttribute("aria-hidden", "true");
        this.insertBefore(target, this.querySelector(".wl-chart-svg"));

        window.vegaEmbed(target, spec, {actions: false, renderer: "svg"})
          .then(() => {
            const fallback = this.querySelector(".wl-chart-svg");
            if (fallback) fallback.hidden = true;
          })
          .catch(() => target.remove());
      }
    }
  };

  if (window.Phoenix && window.LiveView && csrf) {
    const liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, {
      hooks: Hooks,
      params: {_csrf_token: csrf}
    });
    liveSocket.connect();
    window.liveSocket = liveSocket;
  }
})();
