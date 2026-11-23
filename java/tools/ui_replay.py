#!/usr/bin/env python3
"""同一性確認（実 UI 操作 + 録画）: replay.py と同じ比較を、ブラウザの業務画面をキーボード操作して行う。

  python3 tools/ui_replay.py <証跡dir> [--url http://localhost:18080] [--out 結果.json] CASE_ID|PREFIX ...
  環境変数 ACAS_VIDEO=<出力.mp4> で操作を録画する（1280x720, H.264。ffmpeg が必要）。
  CALC- を指定すると計算ロジック画面（calc.html）へ入力して結果をレガシー実測と比較する。

キー入力は Chromium（Playwright）の画面へ実際に打鍵する。画面・レコード・帳票の取得と比較は replay.py と同じ。
ケース ID と名称は画面上部の帯に表示する。
"""
import json, os, shutil, subprocess, sys, tempfile, time
from collections import Counter
from decimal import Decimal
from pathlib import Path
from playwright.sync_api import sync_playwright
sys.path.insert(0, str(Path(__file__).parent))
import replay

PW_KEY = {"ENTER": "Enter", "ESC": "Escape", "TAB": "Tab", "UP": "ArrowUp", "DOWN": "ArrowDown", "LEFT": "ArrowLeft",
          "RIGHT": "ArrowRight", "HOME": "Home", "END": "End", "PGUP": "PageUp", "PGDN": "PageDown",
          "BACKSPACE": "Backspace", "DELETE": "Delete", "BACKTAB": "Shift+Tab"}
STEP_PAUSE = float(os.environ.get("ACAS_STEP_PAUSE", "0.25"))
CASE_PAUSE = float(os.environ.get("ACAS_CASE_PAUSE", "1.2"))


class Browser:
    def __init__(self, url):
        self.url = url.rstrip("/")
        self.video = os.environ.get("ACAS_VIDEO")
        self.tmp = tempfile.mkdtemp(prefix="acas-video-")
        self.pw = sync_playwright().start()
        self.browser = self.pw.chromium.launch(executable_path=os.environ.get("ACAS_CHROMIUM") or None)
        opts = {"viewport": {"width": 1280, "height": 720}, "locale": "ja-JP"}
        if self.video: opts.update(record_video_dir=self.tmp, record_video_size={"width": 1280, "height": 720})
        self.ctx = self.browser.new_context(**opts)
        self.page = self.ctx.new_page()
        self.started = time.monotonic()
        self.page_errors = []
        self.page.on("pageerror", lambda error: self.page_errors.append(str(error)))

    def close(self):
        self.ctx.close(); self.browser.close(); self.pw.stop()
        if self.video:
            webm = next(Path(self.tmp).glob("*.webm"))
            subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(webm), "-c:v", "libx264", "-pix_fmt", "yuv420p",
                            "-r", "25", "-movflags", "+faststart", self.video], check=True)
        shutil.rmtree(self.tmp, ignore_errors=True)


class UiApi(replay.Api):
    """replay.Api のうち「セッション開始」「キー送信」をブラウザ操作に置き換える。"""
    def __init__(self, url):
        super().__init__(url)
        self.b = Browser(url); self.page = self.b.page; self.sid = None

    def before_case(self, case):
        self.b.page_errors.clear()
        self.page.goto(self.url + "/index.html")
        self.page.wait_for_function("typeof window.acasSetCase === 'function'")
        self.page.evaluate("([i, t]) => window.acasSetCase(i, t)", [case["id"], case["title"]])
        self.video_start_seconds = round(time.monotonic() - self.b.started, 2)

    def after_case(self, res):
        res["video_start_seconds"] = self.video_start_seconds if self.b.video else None
        self.page.evaluate("(v) => { document.getElementById('case-banner').textContent += '　判定 ' + v; window.scrollTo(0, 0); }", res["verdict"])
        time.sleep(CASE_PAUSE)

    def idle(self):
        self.page.wait_for_function("() => window.acasIdle()", timeout=25000)
        problem = self.page.locator('#status').inner_text()
        if self.b.page_errors or problem.startswith(('入力を送信できません', '業務を開けません')):
            raise RuntimeError(problem or self.b.page_errors[0])

    def call(self, method, path, body=None):
        if method == "POST" and path.startswith("/api/sessions?"):
            q = dict(p.split("=", 1) for p in path.split("?", 1)[1].split("&"))
            self.page.click("#btn-" + q["app"])
            self.idle()
            self.sid = self.page.evaluate("() => window.acasSessionId()")
            if self.sid is None:
                raise RuntimeError("業務セッションが開始されませんでした")
            return {"id": self.sid}
        if method == "POST" and path.endswith("/keys"):
            keys = body["keys"]
            if len(keys) == 1 and keys[0] != " ":
                for button in self.page.locator("button[data-key]:visible").all():
                    if button.get_attribute("data-key") == keys[0]:
                        button.click()
                        self.idle()
                        time.sleep(STEP_PAUSE)
                        return None
            for k in keys:
                if self.page.evaluate("() => window.acasSessionId()") is None: break   # プログラム終了後は UI が入力を受け付けない
                self.page.keyboard.press(PW_KEY.get(k, "Space" if k == " " else k))
            self.idle(); time.sleep(STEP_PAUSE)
            return None
        return super().call(method, path, body)

    def close(self): self.b.close()


# ---------- CALC（計算ロジック画面） ----------
CALC = {"code": ("check", ["code"]), "date": ("date", ["date"]), "net": ("vat", ["net", "rate"]),
        "days": ("age", ["days"]), "value": ("avg", ["value", "qty"])}


def calc_same(want, got):
    for k, w in want.items():
        g = got.get(k)
        if k in ("vat", "cost"):
            if (w is None) != (g is None) or (w is not None and Decimal(str(w)) != Decimal(str(g))): return False
        elif w != g: return False
    return True


def run_calc(b, case):
    lr, inp = case["legacy_result"], case["input_data"]
    r = {"id": case["id"], "title": case["title"], "legacy_verdict": lr["verdict"], "input": inp}
    page = b.page
    page.evaluate("([i, t]) => window.acasSetCase(i, t)", [case["id"], case["title"]])
    key = next((k for k in CALC if isinstance(inp, dict) and k in inp), None)
    if lr["verdict"] == "未実施" or lr.get("actual") is None or key is None:
        return dict(r, verdict="対象外", reason="レガシー未実施のため比較対象なし: " + str(lr.get("reason") or ""))
    name, fields = CALC[key]
    page.evaluate("(n) => { const o = document.getElementById('o-' + n); o.textContent = ''; delete o.dataset.result; }", name)
    for f in fields: page.fill("#" + f, str(inp.get(f, "")))
    page.click(f"button[data-calc={name}]")
    page.wait_for_function("(n) => document.getElementById('o-' + n).textContent !== ''", arg=name, timeout=30000)
    shown = page.inner_text("#o-" + name)
    raw = page.evaluate("(n) => document.getElementById('o-' + n).dataset.result || ''", name)
    got = json.loads(raw) if raw else {}
    ok = bool(raw) and calc_same(lr["actual"], got)
    r.update(java_actual=got, java_display=shown, legacy_actual=lr["actual"], verdict="一致" if ok else "不一致",
             reason=("計算ロジック画面の結果がレガシー実測と一致: " if ok else
                     "計算結果相違: legacy=" + json.dumps(lr["actual"], ensure_ascii=False) + " java=") + (raw or shown))
    return r


def main_calc(argv):
    import argparse
    ap = argparse.ArgumentParser(); ap.add_argument("evidence", type=Path); ap.add_argument("cases", nargs="+")
    ap.add_argument("--url", default="http://localhost:18080"); ap.add_argument("--out", type=Path)
    a = ap.parse_args(argv)
    cases = [c for c in json.loads((a.evidence / "scenarios/catalog.json").read_text())["cases"]
             if c["subsystem"] == "CALC" and any(c["id"] == x or (x.endswith("-") and c["id"].startswith(x)) for x in a.cases)]
    b = Browser(a.url); b.page.goto(b.url + "/calc.html"); results = []
    b.page.wait_for_function("typeof window.acasSetCase === 'function'")
    for c in cases:
        t = time.monotonic()
        try: r = run_calc(b, c)
        except Exception as e: r = {"id": c["id"], "title": c["title"], "verdict": "未検証", "reason": f"実行エラー: {e}"}
        r["video_start_seconds"] = round(t - b.started, 2) if b.video else None
        b.page.evaluate("(v) => { document.getElementById('case-banner').textContent += '　判定 ' + v; window.scrollTo(0, 0); }", r["verdict"])
        time.sleep(CASE_PAUSE)
        results.append(r); print(r["id"], r["verdict"], r["reason"][:150], flush=True)
    b.close()
    if a.out: a.out.parent.mkdir(parents=True, exist_ok=True); a.out.write_text(json.dumps(results, ensure_ascii=False, indent=1))
    print(dict(Counter(r["verdict"] for r in results)))


if __name__ == "__main__":
    if any(x.startswith("CALC-") for x in sys.argv[1:]): main_calc(sys.argv[1:])
    else: replay.main(UiApi)
