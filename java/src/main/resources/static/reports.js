const list = document.getElementById('reports');
const status = document.getElementById('status');
const dialog = document.getElementById('report');
const title = document.getElementById('report-title');
const content = document.getElementById('report-content');

async function json(url) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(String(response.status));
  return response.json();
}

async function show(file, label) {
  title.textContent = label;
  content.textContent = '帳票を読み込んでいます。';
  dialog.showModal();
  try {
    const report = await json('api/reports/content?name=' + encodeURIComponent(file));
    if (dialog.open && title.textContent === label) content.textContent = report.lines.join('\n');
  } catch {
    if (dialog.open && title.textContent === label) content.textContent = '帳票を読み込めませんでした。';
  }
}

try {
  const reports = await json('api/reports');
  if (!reports.length) status.textContent = '出力済みの帳票はありません。';
  for (const [index, report] of reports.entries()) {
    const row = list.insertRow();
    const label = report.title || '帳票 ' + (index + 1);
    const button = document.createElement('button');
    button.type = 'button';
    button.textContent = label;
    button.addEventListener('click', () => show(report.name, label));
    row.insertCell().append(button);
    row.insertCell().textContent = report.name.startsWith('spool/') ? '印刷済み' : '作成済み';
    row.insertCell().textContent = report.lines;
  }
} catch {
  status.textContent = '帳票一覧を読み込めませんでした。';
}
