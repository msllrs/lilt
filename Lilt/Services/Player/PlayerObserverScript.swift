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
      const state = { video: null, lastTimeUpdate: 0, lastReport: 0, pendingNav: null, hold: false, cueing: null, ytVolume: null, volume: null, probed: false, errorPlayer: null, errorScreenFor: null };
      // A standby page (gapless playback) is held silent and still. The flag outlives a reload
      // through sessionStorage, which belongs to this web view alone.
      const holdKey = '__liltHold';
      try { state.hold = !!sessionStorage.getItem(holdKey); } catch (e) {}
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
      // The player bar's like button: 'LIKE', 'DISLIKE' or 'INDIFFERENT' (empty when not found).
      const likeRenderer = () => document.querySelector('ytmusic-player-bar ytmusic-like-button-renderer');
      const likeStatus = () => { const r = likeRenderer(); return r ? (r.getAttribute('like-status') || '') : ''; };
      // The player bar's byline links to the artist (channel/UC…) and album (browse/MPREb…).
      const links = () => {
        const out = { artistId: '', albumId: '', albumTitle: '' };
        document.querySelectorAll('ytmusic-player-bar .byline a[href]').forEach((a) => {
          const href = a.getAttribute('href') || '';
          const artist = href.match(/channel\/(UC[\w-]+)/);
          if (artist && !out.artistId) { out.artistId = artist[1]; }
          const album = href.match(/browse\/(MPREb_[\w-]+)/);
          if (album && !out.albumId) { out.albumId = album[1]; out.albumTitle = (a.textContent || '').trim(); }
        });
        return out;
      };
      // Muted at the element, never through the player API: that stores volume and mute for
      // every YouTube Music page on the account, the one you're listening to included. The
      // volume YouTube gives the element (its own level, loudness-matched per song) is kept to
      // put back on start.
      const quiet = (v) => {
        if (v.volume > 0) { state.ytVolume = v.volume; }
        if (v.volume !== 0) { v.volume = 0; }
        if (!v.muted) { v.muted = true; }
      };
      // The page autoplays whatever it navigates to; a held one stops it the moment it starts.
      const keepHeld = () => {
        const v = state.video;
        if (!state.hold || !v) { return; }
        quiet(v);
        if (!v.paused) { v.pause(); }
      };
      // A volume Lilt gives the page (an ambience sound's level) is held at the element: YouTube's
      // player puts its own back as a track loads and starts, and now and then as it plays. The
      // listeners sit on the document, capturing, so they're there before the <video> is found.
      const keepVolume = (e) => {
        const v = e.target;
        if (state.volume == null || state.hold || !(v instanceof HTMLMediaElement)) { return; }
        if (Math.abs(v.volume - state.volume) > 0.0001) { v.volume = state.volume; }
      };
      ['loadstart', 'play', 'playing', 'volumechange'].forEach((e) => document.addEventListener(e, keepVolume, true));
      const bufferedAhead = (v) => {
        const t = v.currentTime || 0;
        for (let i = 0; i < v.buffered.length; i++) {
          if (v.buffered.start(i) <= t + 0.1 && v.buffered.end(i) > t) { return v.buffered.end(i) - t; }
        }
        return 0;
      };
      const stopCueing = () => { if (state.cueing) { clearInterval(state.cueing); state.cueing = null; } };
      const hold = () => {
        state.hold = true;
        try { sessionStorage.setItem(holdKey, '1'); } catch (e) {}
        if (state.pendingNav) { clearInterval(state.pendingNav); state.pendingNav = null; }
        keepHeld();
      };
      const release = () => {
        state.hold = false;
        stopCueing();
        try { sessionStorage.removeItem(holdKey); } catch (e) {}
      };
      const report = () => {
        const v = state.video;
        if (!v) { return; }
        state.lastReport = Date.now();
        post('STATE_UPDATE', Object.assign({
          videoId: videoId(),
          isPlaying: !v.paused && !v.ended,
          currentTime: v.currentTime || 0,
          duration: isFinite(v.duration) ? v.duration : 0,
        }, metadata(), links(), { likeStatus: likeStatus() }));
      };
      const attach = (v) => {
        if (state.video === v) { return; }
        state.video = v;
        ['play', 'playing', 'volumechange', 'loadstart'].forEach((e) => v.addEventListener(e, keepHeld));
        ['play', 'pause', 'playing', 'durationchange', 'loadedmetadata', 'seeked', 'emptied'].forEach((e) => v.addEventListener(e, report));
        v.addEventListener('timeupdate', () => {
          const now = Date.now();
          if (now - state.lastTimeUpdate < 500) { return; }
          state.lastTimeUpdate = now;
          report();
        });
        v.addEventListener('ended', () => post('TRACK_ENDED', { videoId: videoId() }));
        // Sound actually under way (not just asked for), for timing the gap between tracks.
        v.addEventListener('playing', () => post('PLAYING', { videoId: videoId() }));
        // What macOS is told about this page as it starts to sound, and again once YouTube
        // Music has had time to fill it in, for the diagnostics log.
        v.addEventListener('playing', () => { reportSession('playing'); setTimeout(() => reportSession('2s later'), 2000); });
        v.addEventListener('error', () => {
          const e = v.error;
          post('PLAYBACK_ERROR', { videoId: videoId(), reason: '<video> error ' + (e ? e.code + (e.message ? ' ' + e.message : '') : '?') });
        });
        keepHeld();
        report();
      };
      // What the page's player offers for gapless playback, for the DEBUG log: whether YouTube
      // would stitch songs into one stream here (it decides by browser: Chrome 74+ or Firefox
      // 68+), and which of its queue and preload methods exist.
      const gaplessApiNames = ['supportsGaplessAudio', 'isGaplessTransitionReady', 'queueNextVideo', 'enqueueVideoByPlayerVars',
        'clearQueue', 'preloadVideoById', 'preloadVideoByPlayerVars', 'nextVideo', 'getPlaylist', 'getPlaylistId'];
      const probe = (why) => {
        const p = document.getElementById('movie_player');
        if (!p) { post('GAPLESS_PROBE', { why, player: false }); return; }
        const has = (o) => gaplessApiNames.filter((n) => o && typeof o[n] === 'function').join(',');
        let supports = 'missing';
        try { if (typeof p.supportsGaplessAudio === 'function') { supports = String(p.supportsGaplessAudio()); } } catch (e) { supports = 'threw'; }
        let internal = 'missing';
        try { if (typeof p.getInternalApi === 'function') { internal = has(p.getInternalApi()); } } catch (e) { internal = 'threw'; }
        post('GAPLESS_PROBE', { why, player: true, supportsGaplessAudio: supports, apis: has(p), internalApis: internal, userAgent: navigator.userAgent });
      };

      // The player's own failures: its onError event (listened to, nothing replaced), and its
      // error screen, once per song.
      const watchErrors = () => {
        const p = playerApi();
        if (p && state.errorPlayer !== p && typeof p.addEventListener === 'function') {
          state.errorPlayer = p;
          try { p.addEventListener('onError', (code) => post('PLAYBACK_ERROR', { videoId: videoId(), reason: 'player onError ' + code })); } catch (e) {}
        }
        const screen = document.querySelector('#movie_player .ytp-error');
        const shown = !!screen && screen.offsetParent !== null;
        const id = videoId();
        if (shown && state.errorScreenFor !== id) {
          state.errorScreenFor = id;
          post('PLAYBACK_ERROR', { videoId: id, reason: 'player error screen: ' + (screen.textContent || '').trim().slice(0, 120) });
        } else if (!shown) {
          state.errorScreenFor = null;
        }
      };

      const tick = () => {
        const v = document.querySelector('video');
        if (v) { attach(v); }
        watchErrors();
        if (!state.probed && playerApi()) { state.probed = true; probe('startup'); }
        // The check reports only what nothing else has: a paused page's late title or like.
        // A held standby's reports would be thrown away, and a playing page's playhead has
        // reported within the second.
        if (!state.hold && Date.now() - state.lastReport >= 900) { report(); }
      };
      setInterval(tick, 1000);
      tick();

      // In-app navigation keeps the YouTube Music shell loaded (~250ms to audio versus seconds
      // for a page load). The app's router listens for `yt-navigate` events carrying a music
      // watch endpoint. We confirm via the player's video id and reload only as a last resort.
      const navigate = (id) => {
        release();
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

      // Gapless playback: the standby page navigates to the next song held silent, then waits
      // paused at 0:00 until enough is buffered to start the instant the current song ends.
      // CUED says it's ready; CUE_FAILED hands the song back to the ordinary load.
      const cue = (id) => {
        hold();
        stopCueing();
        const fallback = (why) => {
          stopCueing();
          post('NAV', { method: 'cue-replace:' + why, id });
          location.replace('https://music.youtube.com/watch?v=' + encodeURIComponent(id));
        };
        if (videoId() !== id) {
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
        }
        const started = Date.now();
        state.cueing = setInterval(() => {
          const elapsed = Date.now() - started;
          const v = state.video;
          if (videoId() === id && v && v.readyState >= 1) {
            keepHeld();
            if (v.currentTime > 0.05 && !v.seeking) { v.currentTime = 0; }
            const wanted = Math.min(5, Math.max(0, (v.duration || 0) - 0.5));
            if (v.paused && !v.seeking && v.currentTime <= 0.05 && v.readyState >= 3 && bufferedAhead(v) >= wanted) {
              stopCueing();
              post('CUED', { videoId: id });
              return;
            }
          } else if (videoId() !== id && elapsed > 6000) {
            fallback('not-cued');
            return;
          }
          if (elapsed > 20000) { stopCueing(); post('CUE_FAILED', { videoId: id }); }
        }, 250);
      };
      // The handover: unmute at YouTube's own level and play straight from the element, which
      // is the quickest way to sound from a buffered pause.
      const start = () => {
        release();
        const v = state.video;
        if (!v) { return; }
        const p = playerApi();
        let volume = state.ytVolume;
        if (volume == null) { try { volume = p && p.getVolume ? p.getVolume() / 100 : 1; } catch (e) { volume = 1; } }
        v.muted = false;
        v.volume = Math.max(0, Math.min(1, volume));
        const r = v.play();
        if (r && r.catch) { r.catch(() => { try { if (p) { p.playVideo(); } } catch (e) {} }); }
      };

      // WebKit publishes the page's Media Session to macOS Now Playing and media keys. Keep that
      // as the single system entry, but make next/previous drive Lilt's queue instead of the
      // page's own, and stop the page from taking those actions back. Pause and play go to
      // Lilt too, which pauses and plays through the page as for its own buttons: that way it
      // knows a pause came from the system (AirPods taken out) and can take the system's Play
      // when they go back in, which after two Pauses no longer reaches this session.
      const ms = navigator.mediaSession;
      // The actions this page's session offers, as set through it (handlers can't be read back).
      const offered = new Set();
      if (ms && typeof ms.setActionHandler === 'function') {
        const original = ms.setActionHandler.bind(ms);
        const offer = (action, handler) => { if (handler) { offered.add(action); } else { offered.delete(action); } return original(action, handler); };
        const ours = {
          nexttrack: () => post('REMOTE', { action: 'next' }),
          previoustrack: () => post('REMOTE', { action: 'previous' }),
          pause: () => post('REMOTE', { action: 'pause' }),
          play: () => post('REMOTE', { action: 'play' }),
        };
        ms.setActionHandler = (action, handler) => offer(action, ours[action] || handler);
        Object.keys(ours).forEach((k) => { try { offer(k, ours[k]); } catch (e) {} });
      }
      function reportSession(when) {
        const m = ms && ms.metadata;
        post('SESSION', {
          when, videoId: videoId() || '', hold: state.hold,
          title: (m && m.title) || '', artist: (m && m.artist) || '', album: (m && m.album) || '',
          artwork: (m && m.artwork) ? m.artwork.length : -1,
          artworkSrc: (m && m.artwork && m.artwork.length) ? String(m.artwork[m.artwork.length - 1].src).slice(0, 80) : '',
          actions: Array.from(offered).sort().join(','),
          playbackState: (ms && ms.playbackState) || '',
          muted: state.video ? (state.video.muted || state.video.volume === 0) : null,
        });
      }

      window.__lilt = {
        navigate,
        cue,
        hold,
        start,
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
        setVolume: (x) => {
          state.volume = Math.max(0, Math.min(1, x));
          const v = state.video || document.querySelector('video');
          if (v && !state.hold) { v.volume = state.volume; }
        },
        // Clicks the page's own like button, so YouTube Music records it and the status above
        // reflects it on the next update.
        toggleLike: () => {
          const r = likeRenderer(); if (!r) { return; }
          const b = r.querySelector('#button-shape-like button') || r.querySelector('yt-button-shape.like button') || r.querySelector('button');
          if (b) { b.click(); }
        },
      };
      post('READY', {});
    })();
    """#
}
