'use strict';

const byId = id => document.getElementById(id);
const screen = byId('screen');
const fields = byId('fields');
const form = byId('operation');
const status = byId('status');
const buttons = byId('actions');
const choices = byId('choices');
const details = byId('details');
const named = {
  Enter: 'ENTER', Escape: 'ESC', Tab: 'TAB', ArrowUp: 'UP', ArrowDown: 'DOWN',
  ArrowLeft: 'LEFT', ArrowRight: 'RIGHT', Home: 'HOME', End: 'END',
  PageUp: 'PGUP', PageDown: 'PGDN', Backspace: 'BACKSPACE', Delete: 'DELETE'
};

let sessionId = null;
let csrfHeaders = {};
let view = null;
let app = null;
let busy = false;
let queue = [];

function element(tag, text, className) {
  const node = document.createElement(tag);
  if (text) node.textContent = text;
  if (className) node.className = className;
  return node;
}

function action(key, label, style, keys = [key]) {
  const button = element('button', label, style);
  button.type = key === 'ENTER' ? 'submit' : 'button';
  button.dataset.key = key;
  if (key !== 'ENTER') button.addEventListener('click', () => send(keys));
  return button;
}

function renderDetails(lines) {
  details.replaceChildren();
  details.hidden = !lines.length;
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    if (line.error || line.cells.length < 2) {
      const message = element('p', line.cells.join('　'), line.error ? 'notice error' : 'notice');
      details.append(message);
      i++;
      continue;
    }

    const table = element('table');
    table.setAttribute('aria-label', '業務データ');
    const tableBody = table.createTBody();
    const columns = line.cells.length;
    if (!line.data && lines[i + 1]?.data && lines[i + 1].cells.length === columns) {
      const header = table.createTHead().insertRow();
      line.cells.forEach(text => {
        const cell = element('th', text);
        cell.scope = 'col';
        header.append(cell);
      });
      i++;
    }
    while (i < lines.length && !lines[i].error && lines[i].cells.length === columns) {
      const row = tableBody.insertRow();
      lines[i].cells.forEach(text => { row.insertCell().textContent = text; });
      i++;
    }
    const scroll = element('div', null, 'table-scroll');
    scroll.append(table);
    details.append(scroll);
  }
}

function render(result, refocus = true) {
  view = result.view;
  const { fields: inputs, choices: options, confirm, cancel, yesNo, actions } = view;
  byId('view-title').textContent = view.title;
  status.textContent = result.ended ? result.endMessage || '業務を終了しました。' : '';
  if (result.ended) {
    sessionId = null;
    app = null;
  }
  for (const name of ['acas', 'irs']) byId('btn-' + name).setAttribute('aria-pressed', String(name === app));

  choices.replaceChildren();
  options.forEach(({ key, label }) => {
    const button = action(key, '', 'choice');
    button.append(element('span', key, 'choice-key'), element('span', label));
    choices.append(button);
  });
  choices.hidden = !options.length;

  fields.replaceChildren();
  buttons.replaceChildren();
  const shown = options.length || yesNo ? [] : inputs;
  shown.forEach(field => {
    const wrapper = element('label', null, 'field');
    wrapper.append(element('span', field.label));
    const input = element('input');
    input.id = 'field-' + field.id;
    input.dataset.field = field.id;
    input.type = field.secure ? 'password' : 'text';
    input.maxLength = field.length;
    input.value = field.value;
    input.spellcheck = false;
    input.autocapitalize = 'off';
    if (field.numeric) input.inputMode = 'decimal';
    wrapper.append(input);
    fields.append(wrapper);
  });
  if (yesNo) {
    const vote = key => view.autoAdvance ? [key] : [key, 'ENTER'];
    buttons.append(action('Y', 'はい', 'primary', vote('Y')), action('N', 'いいえ', null, vote('N')));
  } else if (confirm && !options.length) {
    buttons.append(action('ENTER', '確定', 'primary'));
  }
  if (cancel) buttons.append(action('ESC', '取消・戻る'));
  for (const { key, label } of actions) buttons.append(action(key, label));
  form.hidden = !buttons.children.length && !shown.length;
  renderDetails(view.lines);

  if (!refocus) return;
  const focusedInput = byId('field-' + view.activeField);
  if (focusedInput) {
    focusedInput.focus({ preventScroll: true });
    focusedInput.setSelectionRange(view.caret, view.caret);
  } else {
    screen.focus({ preventScroll: true });
  }
}

async function request(path, options) {
  options.headers = { ...options.headers, ...csrfHeaders };
  const response = await fetch(path, options);
  if (!response.ok) throw new Error(String(response.status));
  if (response.status !== 204 && options.method !== 'DELETE') return response.json();
}

async function start(which) {
  if (busy) return;
  busy = true;
  queue = [];
  status.textContent = '業務を開いています。';
  try {
    csrfHeaders = await request('api/csrf', { method: 'GET' });
    if (sessionId) await request('api/sessions/' + sessionId, { method: 'DELETE' });
    sessionId = null;
    app = null;
    const result = await request('api/sessions?app=' + which, { method: 'POST' });
    sessionId = result.id;
    app = which;
    render(result);
  } catch {
    status.textContent = '業務を開けませんでした。もう一度お試しください。';
  } finally {
    busy = false;
  }
}

function send(keys) {
  if (!sessionId) return;
  queue.push(...keys);
  void flush();
}

async function flush() {
  if (busy || !sessionId || !queue.length) return;
  busy = true;
  try {
    while (sessionId && queue.length) {
      const keys = queue.splice(0, 200);
      const result = await request('api/sessions/' + sessionId + '/keys', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ keys })
      });
      if (!queue.length || result.ended) render(result);
    }
  } catch {
    queue = [];
    status.textContent = '入力を送信できませんでした。もう一度お試しください。';
  } finally {
    busy = false;
  }
}

function editableKeys(input, keys) {
  const { selectionStart, selectionEnd } = input;
  if (selectionStart === selectionEnd) return keys;
  const replacement = ['BACKSPACE', 'DELETE'].includes(keys[0]) ? '' : keys.join('');
  return ['REPLACE:' + selectionStart + ':' + selectionEnd + ':' + replacement];
}

screen.addEventListener('keydown', event => {
  if (!sessionId || event.ctrlKey || event.metaKey || event.altKey || event.isComposing) return;
  const input = event.target instanceof HTMLInputElement;
  if (input && event.shiftKey && ['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
  if (event.target instanceof HTMLButtonElement && ['Enter', ' '].includes(event.key)) return;
  if (event.key === 'Tab' && (!input || !view.multiple)) return;
  if (!input && event.key === ' ' && event.target !== screen) return;
  const key = event.key === 'Tab' && event.shiftKey ? 'BACKTAB' :
    named[event.key] || (/^(?:F(?:[1-9]|1[0-2])|[ -~])$/.test(event.key) ? event.key : null);
  if (key === null) return;
  event.preventDefault();
  const edits = key.length === 1 || key === 'BACKSPACE' || key === 'DELETE';
  send(input && edits ? editableKeys(event.target, [key]) : [key]);
});

fields.addEventListener('beforeinput', event => {
  if (event.isComposing) return;
  event.preventDefault();
  if (event.data) {
    const keys = [...event.data].filter(char => /^[ -~]$/.test(char));
    if (!keys.length) {
      status.textContent = '入力には半角文字を使用してください。';
      return;
    }
    send(editableKeys(event.target, keys.slice(0, Number(event.target.maxLength))));
  }
});

fields.addEventListener('focusin', event => {
  const id = Number(event.target.dataset.field);
  if (!view || busy || !view.multiple || id === view.activeField) return;
  const difference = id - view.activeField;
  send(Array(Math.abs(difference)).fill(difference > 0 ? 'TAB' : 'BACKTAB'));
});

form.addEventListener('submit', event => {
  event.preventDefault();
  send(['ENTER']);
});

for (const name of ['acas', 'irs']) {
  byId('btn-' + name).addEventListener('click', () => start(name));
}

window.addEventListener('pagehide', () => {
  if (!sessionId) return;
  void fetch('api/sessions/' + sessionId, { method: 'DELETE', headers: csrfHeaders, keepalive: true }).catch(() => {});
  sessionId = null;
});

window.addEventListener('pageshow', event => {
  if (event.persisted && app) void start(app);
});

window.acasSetCase = (id, title) => {
  const banner = byId('case-banner');
  banner.hidden = false;
  banner.textContent = 'ケース ' + id + '　' + title;
};
window.acasSessionId = () => sessionId;
window.acasIdle = () => !busy && queue.length === 0;
