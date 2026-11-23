package jp.co.acas.core;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.annotation.PostConstruct;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

import java.io.InputStream;
import java.util.*;

/**
 * レガシーの ISAM/相対/順ファイルに相当するレコード保管庫。
 * 実体は H2 のテーブル ACAS_RECORD（ファイル名＋キー＋レガシー互換バイト列）で、
 * 高速な順読みのためメモリ上にも同じ内容を保持する（書込みは同期して DB へ反映）。
 */
@Component
public class Store {
    private final JdbcTemplate jdbc;
    private final ObjectMapper mapper = new ObjectMapper();
    private final Map<String, TreeMap<byte[], byte[]>> files = new HashMap<>();
    @Value("${acas.initial-baseline:}") private String initialBaseline;

    public Store(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    @PostConstruct
    synchronized void init() {
        jdbc.execute("create table if not exists ACAS_FILE(FNAME varchar(200) primary key)");
        jdbc.execute("create table if not exists ACAS_RECORD(FNAME varchar(200) not null, RKEY varbinary(400) not null, RDATA varbinary(65000) not null, primary key(FNAME, RKEY))");
        jdbc.query("select FNAME from ACAS_FILE", rs -> { files.put(rs.getString(1), newMap()); });
        jdbc.query("select FNAME, RKEY, RDATA from ACAS_RECORD", rs -> {
            files.computeIfAbsent(rs.getString(1), k -> newMap()).put(rs.getBytes(2), rs.getBytes(3));
        });
        if (files.isEmpty() && initialBaseline != null && !initialBaseline.isBlank()) loadBaseline(initialBaseline);
    }
    private static TreeMap<byte[], byte[]> newMap() { return new TreeMap<>(Arrays::compareUnsigned); }

    public synchronized boolean exists(String f) { return files.containsKey(f); }
    public synchronized void create(String f) {
        if (files.containsKey(f)) { jdbc.update("delete from ACAS_RECORD where FNAME=?", f); files.get(f).clear(); }
        else { jdbc.update("insert into ACAS_FILE values(?)", f); files.put(f, newMap()); }
    }
    public synchronized void deleteFile(String f) {
        if (files.remove(f) != null) { jdbc.update("delete from ACAS_RECORD where FNAME=?", f); jdbc.update("delete from ACAS_FILE where FNAME=?", f); }
    }
    public synchronized byte[] get(String f, byte[] k) { var m = files.get(f); return m == null ? null : m.get(k); }
    public synchronized void put(String f, byte[] k, byte[] d) {
        var m = files.get(f);
        if (m == null) { create(f); m = files.get(f); }
        boolean had = m.put(k.clone(), d.clone()) != null;
        if (had) jdbc.update("update ACAS_RECORD set RDATA=? where FNAME=? and RKEY=?", d, f, k);
        else jdbc.update("insert into ACAS_RECORD values(?,?,?)", f, k, d);
    }
    public synchronized boolean remove(String f, byte[] k) {
        var m = files.get(f);
        if (m == null || m.remove(k) == null) return false;
        jdbc.update("delete from ACAS_RECORD where FNAME=? and RKEY=?", f, k);
        return true;
    }
    /** k より大きい（inclusive なら以上の）最小キーのエントリ。 */
    public synchronized Map.Entry<byte[], byte[]> next(String f, byte[] k, boolean inclusive) {
        var m = files.get(f);
        if (m == null) return null;
        return k == null ? m.firstEntry() : inclusive ? m.ceilingEntry(k) : m.higherEntry(k);
    }
    public synchronized Map.Entry<byte[], byte[]> prev(String f, byte[] k, boolean inclusive) {
        var m = files.get(f);
        if (m == null) return null;
        return k == null ? m.lastEntry() : inclusive ? m.floorEntry(k) : m.lowerEntry(k);
    }
    public synchronized List<Map.Entry<byte[], byte[]>> all(String f) {
        var m = files.get(f);
        return m == null ? List.of() : new ArrayList<>(m.entrySet());
    }
    public synchronized int count(String f) { var m = files.get(f); return m == null ? 0 : m.size(); }
    public synchronized List<String> fileNames() { return new ArrayList<>(new TreeSet<>(files.keySet())); }

    /** 全ファイルの論理スナップショット（16進）。同一性検証で before/after 比較に使う。 */
    public synchronized Map<String, Map<String, String>> snapshot() {
        Map<String, Map<String, String>> out = new TreeMap<>();
        HexFormat hex = HexFormat.of();
        files.forEach((f, m) -> {
            Map<String, String> recs = new LinkedHashMap<>();
            m.forEach((k, d) -> recs.put(hex.formatHex(k), hex.formatHex(d)));
            out.put(f, recs);
        });
        return out;
    }

    public synchronized void clearAll() {
        jdbc.update("delete from ACAS_RECORD"); jdbc.update("delete from ACAS_FILE"); files.clear();
    }

    /** resources/baselines/<name>.json（{file:{keyHex:dataHex}}）を読み込み、全データを置き換える。 */
    public synchronized void loadBaseline(String name) {
        if (!name.matches("[A-Za-z0-9_-]+")) throw new IllegalArgumentException("不正なベースライン名");
        clearAll();
        try (InputStream in = Store.class.getResourceAsStream("/baselines/" + name + ".json")) {
            if (in == null) throw new IllegalArgumentException("ベースラインがありません: " + name);
            JsonNode root = mapper.readTree(in);
            HexFormat hex = HexFormat.of();
            List<Object[]> batch = new ArrayList<>();
            root.fields().forEachRemaining(fe -> {
                create(fe.getKey());
                var m = files.get(fe.getKey());
                fe.getValue().fields().forEachRemaining(re -> {
                    byte[] k = hex.parseHex(re.getKey()), d = hex.parseHex(re.getValue().asText());
                    m.put(k, d); batch.add(new Object[]{fe.getKey(), k, d});
                });
            });
            jdbc.batchUpdate("insert into ACAS_RECORD values(?,?,?)", batch);
        } catch (java.io.IOException e) { throw new IllegalStateException(e); }
    }
}
