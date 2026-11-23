package jp.co.acas.web;

import jp.co.acas.calc.Calc;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;

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
        return one("vat", Calc.vat(dec(net, "税抜金額"), dec(rate, "税率")).toPlainString());
    }

    @GetMapping("/age")
    public Map<String, Object> age(@RequestParam int days) {
        return one("bucket", Calc.ageBucket(days));
    }

    @GetMapping("/average-cost")
    public Map<String, Object> averageCost(@RequestParam String value, @RequestParam long qty) {
        BigDecimal c = Calc.averageCost(dec(value, "在庫金額"), qty);
        return one("cost", c == null ? null : c.toPlainString());
    }

    @ExceptionHandler(ResponseStatusException.class)
    ResponseEntity<Map<String, Object>> inputError(ResponseStatusException error) {
        return ResponseEntity.status(error.getStatusCode()).body(one("message", error.getReason()));
    }

    @ExceptionHandler(MissingServletRequestParameterException.class)
    ResponseEntity<Map<String, Object>> missingInput() {
        return ResponseEntity.badRequest().body(one("message", "必要な項目を入力してください。"));
    }

    @ExceptionHandler(MethodArgumentTypeMismatchException.class)
    ResponseEntity<Map<String, Object>> invalidInteger(MethodArgumentTypeMismatchException error) {
        String field = error.getName().equals("days") ? "経過日数" : "数量";
        return ResponseEntity.badRequest().body(one("message", field + "は整数で入力してください。"));
    }

    private static String limit(String s) {
        if (s.length() > 64) throw badInput("入力が長すぎます。");
        return s;
    }

    private static BigDecimal dec(String s, String field) {
        try {
            if (s.length() > 32) throw new NumberFormatException();
            BigDecimal d = new BigDecimal(s.trim());
            if (Math.abs(d.scale()) > 12 || d.precision() > 24) throw new NumberFormatException();
            return d;
        } catch (NumberFormatException e) { throw badInput(field + "の数値が不正です。"); }
    }

    private static ResponseStatusException badInput(String message) {
        return new ResponseStatusException(HttpStatus.BAD_REQUEST, message);
    }

    private static Map<String, Object> one(String k, Object v) { Map<String, Object> m = new LinkedHashMap<>(); m.put(k, v); return m; }
}
