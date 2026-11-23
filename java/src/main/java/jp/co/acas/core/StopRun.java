package jp.co.acas.core;

/** COBOL の STOP RUN 相当（実行単位の終了）。 */
public class StopRun extends RuntimeException {
    public StopRun(String message) { super(message, null, false, false); }
    public StopRun() { this(""); }
}
