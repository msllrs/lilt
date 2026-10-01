import Foundation

/// JavaScript injected into the hidden YouTube Music web view. It watches the `<video>` element
/// and posts `STATE_UPDATE` / `TRACK_ENDED` messages to the `lilt` handler, and exposes
/// `window.__lilt` for native control.
enum PlayerObserverScript {
    static let source = #"""
    (() => {
      if (window.__lilt) { return; }
      const post = (type, payload) => {
        try { window.webkit.messageHandlers.lilt.postMessage(Object.assign({ type }, payload || {})); } catch (e) {}
      };
      const state = { video: null, lastTimeUpdate: 0 };
      const videoId = () => new URLSearchParams(location.search).get('v');
      const text = (sel) => { const el = document.querySelector(sel); return el ? (el.textContent || '').trim() : ''; };
      const metadata = () => {
        const m = navigator.mediaSession && navigator.mediaSession.metadata;
        const title = (m && m.title) || text('ytmusic-player-bar .title');
        const artist = (m && m.artist) || text('ytmusic-player-bar .byline');
        let artworkURL = '';
        if (m && m.artwork && m.artwork.length) { artworkURL = m.artwork[m.artwork.length - 1].src || ''; }
        if (!artworkURL) { const img = document.querySelector('ytmusic-player-bar img.image'); artworkURL = img ? img.src : ''; }
        return { title, artist, artworkURL };
      };
      const report = () => {
        const v = state.video;
        if (!v) { return; }
        post('STATE_UPDATE', Object.assign({
          videoId: videoId(),
          isPlaying: !v.paused && !v.ended,
          currentTime: v.currentTime || 0,
          duration: isFinite(v.duration) ? v.duration : 0,
        }, metadata()));
      };
      const attach = (v) => {
        if (state.video === v) { return; }
        state.video = v;
        ['play', 'pause', 'playing', 'durationchange', 'loadedmetadata', 'seeked', 'emptied'].forEach((e) => v.addEventListener(e, report));
        v.addEventListener('timeupdate', () => {
          const now = Date.now();
          if (now - state.lastTimeUpdate < 500) { return; }
          state.lastTimeUpdate = now;
          report();
        });
        v.addEventListener('ended', () => post('TRACK_ENDED', { videoId: videoId() }));
        report();
      };
      const tick = () => {
        const v = document.querySelector('video');
        if (v) { attach(v); }
        report();
      };
      setInterval(tick, 1000);
      tick();
      window.__lilt = {
        play: () => { const v = state.video; if (v) { const p = v.play(); if (p && p.catch) { p.catch(() => {}); } } },
        pause: () => { if (state.video) { state.video.pause(); } },
        seek: (t) => { if (state.video) { state.video.currentTime = t; } },
        setVolume: (x) => { if (state.video) { state.video.volume = Math.max(0, Math.min(1, x)); } },
      };
      post('READY', {});
    })();
    """#
}
