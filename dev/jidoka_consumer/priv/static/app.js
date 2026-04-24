(() => {
  if (window.__jidokaLiveSocket) return;

  const csrfToken = document
    .querySelector("meta[name='csrf-token']")
    ?.getAttribute("content");

  if (!csrfToken || !window.Phoenix || !window.LiveView) return;

  const liveSocket = new window.LiveView.LiveSocket(
    "/live",
    window.Phoenix.Socket,
    { params: { _csrf_token: csrfToken } },
  );

  liveSocket.connect();
  window.__jidokaLiveSocket = liveSocket;
})();
