(() => {
  const csrf = document.querySelector("meta[name='csrf-token']")?.getAttribute("content");

  const chartOptions = (element) => {
    const style = getComputedStyle(element);
    const color = (role) => style.getPropertyValue(`--wl-color-${role}`).trim();
    return {
      actions: false, renderer: "svg", ast: true, defaultStyle: false, tooltip: false,
      // No external data is admitted server-side; also refuse renderer I/O.
      loader: {
        load: () => Promise.reject(new Error("Chart data URLs are disabled")),
        sanitize: () => Promise.reject(new Error("Chart links are disabled"))
      },
      config: {
        background: color("bg"),
        axis: {labelColor: color("text"), titleColor: color("text"), gridColor: color("border")},
        legend: {labelColor: color("text"), titleColor: color("text")},
        title: {color: color("text")},
        range: {category: ["accent", "success", "warning", "danger", "text", "muted", "focus", "border"].map(color)}
      }
    };
  };

  const renderChart = (hook) => {
    const generation = ++hook.generation;
    hook.result?.finalize();
    hook.result = null;
    const fallback = hook.el.querySelector(".wl-chart-svg");
    const target = hook.el.querySelector(".wl-chart-enhanced");
    const reset = hook.el.querySelector("[data-chart-reset]");
    fallback.removeAttribute("hidden");
    target.hidden = true;
    reset.hidden = true;
    target.replaceChildren();
    if (!window.vegaEmbed || hook.disposed) return;

    const pending = document.createElement("div");
    target.appendChild(pending);
    let work;
    try {
      const spec = JSON.parse(hook.el.dataset.spec);
      // This fixed selection is host-owned, never merged from caller params.
      spec.params = [{name: "wotex_zoom", select: {type: "interval", encodings: ["x"]}, bind: "scales"}];
      work = window.vegaEmbed(pending, spec, chartOptions(hook.el));
    } catch (_error) {
      pending.remove();
      return;
    }

    Promise.resolve(work).then((result) => {
      if (hook.disposed || generation !== hook.generation) {
        result.finalize();
        pending.remove();
        return;
      }
      hook.result = result;
      fallback.setAttribute("hidden", "");
      target.hidden = false;
      reset.hidden = false;
    }).catch(() => {
      pending.remove();
      if (!hook.disposed && generation === hook.generation) {
        fallback.removeAttribute("hidden");
        target.hidden = true;
        reset.hidden = true;
      }
    });
  };

  const Hooks = {
    WotexChart: {
      mounted() {
        this.generation = 0;
        this.disposed = false;
        this.reset = () => renderChart(this);
        this.el.querySelector("[data-chart-reset]").addEventListener("click", this.reset);
        this.themeObserver = new MutationObserver(this.reset);
        const shell = this.el.closest(".wotex-lab");
        if (shell) this.themeObserver.observe(shell, {attributes: true, attributeFilter: ["data-theme"]});
        this.media = window.matchMedia("(prefers-color-scheme: dark)");
        this.media.addEventListener("change", this.reset);
        renderChart(this);
      },
      updated() { renderChart(this); },
      destroyed() {
        this.disposed = true;
        ++this.generation;
        this.result?.finalize();
        this.result = null;
        this.themeObserver.disconnect();
        this.media.removeEventListener("change", this.reset);
        this.el.querySelector("[data-chart-reset]").removeEventListener("click", this.reset);
      }
    }
  };

  if (window.Phoenix && window.LiveView && csrf) {
    const liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, {
      hooks: Hooks, params: {_csrf_token: csrf}
    });
    liveSocket.connect();
    window.liveSocket = liveSocket;
  }
})();
