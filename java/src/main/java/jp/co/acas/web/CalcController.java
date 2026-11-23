package jp.co.acas.web;

import jp.co.acas.calc.Calc;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.util.LinkedHashMap;
import java.util.Map;

/** 計算ロジックの単体実行（画面 calc.html から利用）。 */
@RestController
@RequestMapping("/api/calc")
public class CalcController {
    @GetMapping("/check-digit")
    public Map<String, Object> checkDigit(@RequestParam String code) { return Calc.checkDigit(limit(code)); }

    @GetMapping("/date")
    public Map<String, Object> date(@RequestParam String date) { return Calc.date(limit(date)); }

    @GetMapping("/vat")
    public Map<String, Object> vat(@RequestParam String net, @RequestParam String rate) {
        return one("vat", Calc.vat(dec(net), dec(rate)).toPlainString());
    }
    @GetMapping("/age")
    public Map<String, Object> age(@RequestParam int days) { return one("bucket", Calc.ageBucket(days)); }

    @GetMapping("/average-cost")
    public Map<String, Object> averageCost(@RequestParam String value, @RequestParam long qty) {
        BigDecimal c = Calc.averageCost(dec(value), qty);
        return one("cost", c == null ? null : c.toPlainString());
    }

    private static String limit(String s) {
        if (s.length() > 64) throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "入力が長すぎます");
        return s;
    }
    private static BigDecimal dec(String s) {
        try {
            if (s.length() > 32) throw new NumberFormatException();
            BigDecimal d = new BigDecimal(s.trim());
            if (Math.abs(d.scale()) > 12 || d.precision() > 24) throw new NumberFormatException();
            return d;
        } catch (NumberFormatException e) { throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "数値が不正です"); }
    }
    private static Map<String, Object> one(String k, Object v) { Map<String, Object> m = new LinkedHashMap<>(); m.put(k, v); return m; }
}
