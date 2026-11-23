(function () {
  'use strict';
  const screenEl = document.getElementById('screen');
  const statusEl = document.getElementById('status');
  let sessionId = null, busy = false, queue = [];
  const wide = ch => { const c = ch.charCodeAt(0); return c >= 0x1100 && !(c >= 0xff61 && c <= 0xff9f); };

  function render(s) {
    screenEl.textContent = '';
    s.rows.forEach((row, r) => {
      const div = document.createElement('div');
      div.className = 'row';
      let col = 0;
      for (let i = 0; i < row.length; i++) {
        const ch = row[i], w = wide(ch);
        const span = document.createElement('span');
        span.className = 'cell c' + s.colors[r][i] + (w ? ' w' : '');
        if (r === s.cursorRow && col === s.cursorCol && !s.ended) span.className += ' cur';
        span.textContent = ch;
        div.appendChild(span);
        col += w ? 2 : 1;
      }
      screenEl.appendChild(div);
    });
    if (s.ended) {
      statusEl.textContent = 'プログラムを終了しました。' + (s.endMessage || '') + ' 再開するには起動ボタンを押してください。';
      sessionId = null;
    } else statusEl.textContent = '';
  }

  async function start(app) {
    const res = await fetch('api/sessions?app=' + app, { method: 'POST' });
    const s = await res.json();
    sessionId = s.id; queue = [];
    render(s);
    screenEl.focus();
  }
  async function pump() {
    if (busy || !sessionId || queue.length === 0) return;
    busy = true;
    const keys = queue; queue = [];
    try {
      const res = await fetch('api/sessions/' + sessionId + '/keys', {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ keys })
      });
      if (res.ok) render(await res.json()); else statusEl.textContent = '通信エラーが発生しました（' + res.status + '）';
    } catch (e) { statusEl.textContent = '通信エラーが発生しました'; }
    busy = false;
    pump();
  }
  const NAMED = { Enter: 'ENTER', Escape: 'ESC', Tab: 'TAB', ArrowUp: 'UP', ArrowDown: 'DOWN', ArrowLeft: 'LEFT', ArrowRight: 'RIGHT',
    Home: 'HOME', End: 'END', PageUp: 'PGUP', PageDown: 'PGDN', Backspace: 'BACKSPACE', Delete: 'DELETE' };
  screenEl.addEventListener('keydown', ev => {
    if (!sessionId || ev.ctrlKey || ev.metaKey || ev.altKey) return;
    let k = null;
    if (ev.key === 'Tab' && ev.shiftKey) k = 'BACKTAB';
    else if (NAMED[ev.key]) k = NAMED[ev.key];
    else if (/^F\d{1,2}$/.test(ev.key)) k = ev.key;
    else if (ev.key.length === 1) k = ev.key;
    if (k === null) return;
    ev.preventDefault();
    queue.push(k);
    pump();
  });
  document.getElementById('btn-acas').addEventListener('click', () => start('acas'));
  document.getElementById('btn-irs').addEventListener('click', () => start('irs'));
  // 検証動画用: ?case=ID&title=名称 でケース ID と名称を画面内に表示する
  const q = new URLSearchParams(location.search);
  if (q.get('case')) {
    const b = document.getElementById('case-banner');
    b.hidden = false;
    b.textContent = 'ケース ' + q.get('case') + '： ' + (q.get('title') || '');
  }
  window.acasSetCase = (id, title) => { const b = document.getElementById('case-banner'); b.hidden = false; b.textContent = 'ケース ' + id + '： ' + title; };
  window.acasStart = start;
  window.acasSessionId = () => sessionId;
  if (q.get('app')) start(q.get('app'));
})();
