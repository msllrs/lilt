import Foundation

/// JavaScript injected into the hidden YouTube Music web view (page world, so it can reach the
/// app's router and player API). It watches the `<video>` element and posts `STATE_UPDATE` /
/// `TRACK_ENDED` messages to the `lilt` handler, and exposes `window.__lilt` for native control.
enum PlayerObserverScript {
    static let source = #"""
    (() => {
      if (window.__lilt) { return; }
      const post = (type, payload) => {
        try { window.webkit.messageHandlers.lilt.postMessage(Object.assign({ type }, payload || {})); } catch (e) {}
      };
      const state = { video: null, lastTimeUpdate: 0, pendingNav: null };
      const text = (sel) => { const el = document.querySelector(sel); return el ? (el.textContent || '').trim() : ''; };
      const app = () => document.querySelector('ytmusic-app');
      const playerApi = () => {
        const p = document.getElementById('movie_player');
        return (p && typeof p.playVideo === 'function') ? p : null;
      };
      const playerData = () => { try { const p = playerApi(); return p && p.getVideoData ? (p.getVideoData() || {}) : {}; } catch (e) { return {}; } };
      const videoId = () => playerData().video_id || new URLSearchParams(location.search).get('v');
      const metadata = () => {
        const m = navigator.mediaSession && navigator.mediaSession.metadata;
        const d = playerData();
        const title = (m && m.title) || text('ytmusic-player-bar .title') || d.title || '';
        const artist = (m && m.artist) || text('ytmusic-player-bar .byline') || d.author || '';
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

      // In-app navigation keeps the YouTube Music shell loaded (~250ms to audio versus seconds
      // for a page load). The app's router listens for `yt-navigate` events carrying a music
      // watch endpoint. We confirm via the player's video id and reload only as a last resort.
      const navigate = (id) => {
        if (state.pendingNav) { clearInterval(state.pendingNav); state.pendingNav = null; }
        const target = 'https://music.youtube.com/watch?v=' + encodeURIComponent(id);
        const fallback = (why) => {
          clearInterval(state.pendingNav); state.pendingNav = null;
          post('NAV', { method: 'replace:' + why, id });
          location.replace(target);
        };
        const a = app();
        if (!a) { fallback('no-app'); return; }
        const endpoint = {
          watchEndpoint: {
            videoId: id,
            watchEndpointMusicSupportedConfigs: { watchEndpointMusicConfig: { musicVideoType: 'MUSIC_VIDEO_TYPE_ATV' } },
          },
        };
        try {
          a.dispatchEvent(new CustomEvent('yt-navigate', { detail: { endpoint }, bubbles: true, composed: true }));
        } catch (e) { fallback('threw'); return; }
        const started = Date.now();
        let kicked = false;
        state.pendingNav = setInterval(() => {
          const elapsed = Date.now() - started;
          const v = state.video;
          if (videoId() === id) {
            if (v && !v.paused) {
              clearInterval(state.pendingNav); state.pendingNav = null;
              post('NAV', { method: 'router', id });
              return;
            }
            if (!kicked && elapsed > 600) { kicked = true; const p = playerApi(); try { p ? p.playVideo() : (v && v.play()); } catch (e) {} }
            if (elapsed > 8000) { fallback('cued-but-stuck'); }
          } else if (elapsed > 4000) {
            fallback('not-cued');
          }
        }, 100);
      };

      window.__lilt = {
        navigate,
        play: () => {
          const p = playerApi();
          if (p) { p.playVideo(); return; }
          const v = state.video; if (v) { const r = v.play(); if (r && r.catch) { r.catch(() => {}); } }
        },
        pause: () => {
          const p = playerApi();
          if (p) { p.pauseVideo(); return; }
          if (state.video) { state.video.pause(); }
        },
        seek: (t) => {
          const p = playerApi();
          if (p && typeof p.seekTo === 'function') { p.seekTo(t, true); return; }
          if (state.video) { state.video.currentTime = t; }
        },
        setVolume: (x) => { if (state.video) { state.video.volume = Math.max(0, Math.min(1, x)); } },
      };
      post('READY', {});
    })();
    """#
}
