(() => {
  const csrf = document.querySelector("meta[name='csrf-token']")?.getAttribute("content");

  if (window.Phoenix && window.LiveView && csrf) {
    const liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, {
      params: {_csrf_token: csrf}
    });
    liveSocket.connect();
    window.liveSocket = liveSocket;
  }
})();
