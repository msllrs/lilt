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
      const state = { video: null, lastTimeUpdate: 0, pendingNav: null, hold: false, cueing: null, ytVolume: null, probed: false, queueing: null };
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

      const tick = () => {
        const v = document.querySelector('video');
        if (v) { attach(v); }
        if (!state.probed && playerApi()) { state.probed = true; probe('startup'); }
        report();
      };
      setInterval(tick, 1000);
      tick();

      // In-app navigation keeps the YouTube Music shell loaded (~250ms to audio versus seconds
      // for a page load). The app's router listens for `yt-navigate` events carrying a music
      // watch endpoint. We confirm via the player's video id and reload only as a last resort.
      const navigate = (id) => {
        release();
        cancelQueueNext();
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
        cancelQueueNext();
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

      // Gapless, native queue: makes `target` the song right after `source` in YouTube Music's
      // own Up Next, so the page's player moves on to it by itself when `source` ends. It goes
      // through the player bar's "Play next" item, the way you would, with the item's
      // queueAddEndpoint pointed at `target` for the one click (the approach Kaset ships). That
      // endpoint only edits this session's queue; nothing is saved to the account. Reports
      // QUEUE_NEXT { ok, reason } only once the rendered queue reads back `target` straight
      // after the selected `source` row.
      const playNextIcon = 'M6 2.86V5H3a1 1 0 00-1 1v12a1 1 0 102 0V7h2v2.137a.5.5 0 00.748.434L13 5.998 6.748 2.426A.5.5 0 006 2.86ZM21 5h-5a1 1 0 100 2h5a1 1 0 100-2Zm0 6H9a1 1 0 000 2h12a1 1 0 000-2Zm0 6H9a1 1 0 000 2h12a1 1 0 000-2Z';
      const rowVideoId = (data) => {
        if (!data || typeof data !== 'object') { return ''; }
        if (typeof data.videoId === 'string') { return data.videoId; }
        const seen = new Set();
        const visit = (o, depth) => {
          if (!o || typeof o !== 'object' || depth > 6 || seen.has(o)) { return ''; }
          seen.add(o);
          if (typeof o.videoId === 'string' && o.videoId) { return o.videoId; }
          for (const k of Object.keys(o).slice(0, 60)) { const found = visit(o[k], depth + 1); if (found) { return found; } }
          return '';
        };
        return visit(data, 0);
      };
      const queueRows = () => Array.from(document.querySelectorAll(
        'ytmusic-player-queue-item, ytmusic-player-queue-item-renderer, ytmusic-player-queue ytmusic-responsive-list-item-renderer'
      )).map((el) => ({
        videoId: rowVideoId(el.data || el.__data || null),
        selected: el.hasAttribute('selected') || el.hasAttribute('is-playlist-panel-video-renderer-selected') || el.getAttribute('aria-current') === 'true',
      })).filter((r) => r.videoId || r.selected);
      const selectedRow = (rows) => {
        let found = -1;
        for (let i = 0; i < rows.length; i++) { if (rows[i].selected) { if (found >= 0) { return -1; } found = i; } }
        return found;
      };
      const isLinedUp = (rows, source, target) => {
        const i = selectedRow(rows);
        return i >= 0 && rows[i].videoId === source && !!rows[i + 1] && rows[i + 1].videoId === target;
      };
      const playerBarMenuButton = () => {
        const bar = document.querySelector('ytmusic-player-bar') || document.querySelector('[slot="player-bar"]');
        if (!bar) { return null; }
        return bar.querySelector('.middle-controls-buttons ytmusic-menu-renderer button')
          || bar.querySelector('.ytMusicMiniPlayerMenuButton button')
          || Array.from(bar.querySelectorAll('button')).find((b) => (b.getAttribute('aria-label') || '').toLowerCase() === 'action menu')
          || null;
      };
      // Only an item whose endpoint is a queueAddEndpoint is ever clicked, so a changed menu
      // can't make this save, like or share anything.
      const playNextItem = () => {
        const items = Array.from(document.querySelectorAll('ytmusic-menu-popup-renderer ytmusic-menu-service-item-renderer'));
        const endpointOf = (item) => {
          const d = item.data || item.__data || null;
          const e = d && (d.serviceEndpoint || d.navigationEndpoint || d.endpoint);
          return e && e.queueAddEndpoint ? e.queueAddEndpoint : null;
        };
        const byIcon = items.find((i) => i.querySelector && i.querySelector('path[d="' + playNextIcon + '"]') && endpointOf(i));
        const byPosition = items.find((i) => { const q = endpointOf(i); return q && q.queueInsertPosition === 'INSERT_AFTER_CURRENT_VIDEO'; });
        const item = byIcon || byPosition || null;
        return item ? { item, endpoint: endpointOf(item), count: items.length } : { item: null, endpoint: null, count: items.length };
      };
      const cancelQueueNext = () => {
        const q = state.queueing;
        if (!q) { return; }
        state.queueing = null;
        q.timers.forEach((t) => clearTimeout(t));
        if (q.menuOpen) { q.menuOpen = false; try { document.body.click(); } catch (e) {} }
      };
      const queueNext = (target, source, attempt) => {
        cancelQueueNext();
        probe('queue');
        const q = { attempt, timers: [], menuOpen: false, clicked: false };
        state.queueing = q;
        const started = Date.now();
        const live = () => state.queueing === q;
        const later = (fn, ms) => { q.timers.push(setTimeout(() => { if (live()) { fn(); } }, ms)); };
        const finish = (ok, reason) => {
          if (!live()) { return; }
          cancelQueueNext();
          post('QUEUE_NEXT', { videoId: target, source, attempt, ok, reason });
        };
        const retry = (reason) => {
          if (q.menuOpen) { q.menuOpen = false; try { document.body.click(); } catch (e) {} }
          if (Date.now() - started < 8000) { later(tryOnce, 150); } else { finish(false, reason); }
        };
        const verify = (before, since) => {
          if (videoId() !== source) { finish(false, 'source-changed-before-readback'); return; }
          const rows = queueRows();
          const changed = rows.map((r) => r.videoId).join() !== before;
          if (changed && isLinedUp(rows, source, target)) { finish(true, 'queue-readback-confirmed'); return; }
          if (Date.now() - since > 6000) { finish(false, 'queue-readback-timeout'); return; }
          later(() => verify(before, since), 100);
        };
        const fromMenu = () => {
          const found = playNextItem();
          if (!found.count) { if (Date.now() - started < 8000) { later(fromMenu, 50); } else { finish(false, 'menu-did-not-open'); } return; }
          if (!found.item || typeof found.item.click !== 'function') { finish(false, 'play-next-item-not-found'); return; }
          const queueTarget = found.endpoint.queueTarget;
          if (!queueTarget || typeof queueTarget.videoId !== 'string') { finish(false, 'play-next-endpoint-unavailable'); return; }
          // The menu still describes the song before (it re-renders a beat after a change).
          if (queueTarget.videoId !== source) { retry('menu-source-mismatch'); return; }
          const rows = queueRows();
          const i = selectedRow(rows);
          // Without the source selected in the queue, YouTube takes the endpoint's onEmptyQueue
          // path and plays `target` at once; wait for the queue instead.
          if (i < 0 || rows[i].videoId !== source) { retry('queue-source-not-ready'); return; }
          if (isLinedUp(rows, source, target)) {
            if (q.menuOpen) { q.menuOpen = false; try { document.body.click(); } catch (e) {} }
            finish(true, 'already-next');
            return;
          }
          const onEmpty = queueTarget.onEmptyQueue && queueTarget.onEmptyQueue.watchEndpoint;
          const originalTarget = queueTarget.videoId;
          const originalEmpty = onEmpty ? onEmpty.videoId : undefined;
          const restore = () => { queueTarget.videoId = originalTarget; if (onEmpty) { onEmpty.videoId = originalEmpty; } };
          const before = rows.map((r) => r.videoId).join();
          queueTarget.videoId = target;
          if (onEmpty) { onEmpty.videoId = target; }
          q.clicked = true;
          try { found.item.click(); } catch (e) { restore(); finish(false, 'play-next-click-threw'); return; }
          setTimeout(restore, 0);
          if (q.menuOpen) { q.menuOpen = false; try { document.body.click(); } catch (e) {} }
          later(() => verify(before, Date.now()), 0);
        };
        const tryOnce = () => {
          if (videoId() !== source) {
            if (Date.now() - started < 8000) { later(tryOnce, 150); } else { finish(false, 'source-not-playing'); }
            return;
          }
          const button = playerBarMenuButton();
          if (!button) { retry('player-bar-menu-not-found'); return; }
          q.menuOpen = true;
          try { button.click(); } catch (e) { finish(false, 'menu-click-threw'); return; }
          later(fromMenu, 0);
        };
        tryOnce();
      };

      // WebKit publishes the page's Media Session to macOS Now Playing and media keys. Keep that
      // as the single system entry, but make next/previous drive Lilt's queue instead of the
      // page's own, and stop the page from taking those two actions back.
      const ms = navigator.mediaSession;
      if (ms && typeof ms.setActionHandler === 'function') {
        const original = ms.setActionHandler.bind(ms);
        const ours = {
          nexttrack: () => post('REMOTE', { action: 'next' }),
          previoustrack: () => post('REMOTE', { action: 'previous' }),
        };
        ms.setActionHandler = (action, handler) => original(action, ours[action] || handler);
        Object.keys(ours).forEach((k) => { try { original(k, ours[k]); } catch (e) {} });
      }

      window.__lilt = {
        navigate,
        cue,
        queueNext,
        cancelQueueNext,
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
        setVolume: (x) => { if (state.video) { state.video.volume = Math.max(0, Math.min(1, x)); } },
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
