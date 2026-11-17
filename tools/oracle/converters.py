"""Decode bridge exports and SL070's fixed-column printer output."""

import re


def data_records(content):
    result = {"analysis": [], "suppliers": []}
    for line in content.splitlines():
        if line.startswith("A") and 10 <= len(line) <= 37:
            record = line.ljust(37)
            ledger, code, gl = record[1], record[2:4], record[4:10]
            description, reference = record[10:34].rstrip(), record[34:37].rstrip()
            if ledger not in ("P", "S") or not re.fullmatch(r"\d{6}", gl):
                raise ValueError(f"Invalid analysis record: {line!r}")
            result["analysis"].append(dict(ledger=ledger, code=code.rstrip(),
                                           gl=int(gl), description=description,
                                           print=reference))
        elif line.startswith("P") and 8 <= len(line) <= 38:
            result["suppliers"].append(dict(code=line[1:8].rstrip(), name=line[8:].rstrip()))
        else:
            raise ValueError(f"Unknown bridge record: {line!r}")
    return result


def report_json(content):
    lines = [line.rstrip() for line in content.replace("\f", "\n").splitlines()
             if line.strip()]
    if not lines:
        return {"lines": [], "records": []}
    if not any("Product Analysis Codes" in line for line in lines):
        raise ValueError("Not an SL070 analysis report")
    records = []
    for line in lines:
        if line[63:69].strip() in ("Group", "Detail"):
            records.append({"ledger": line[1:2].strip(), "code": line[5:12].strip(),
                            "gl": int(line[12:18].strip() or "0"),
                            "description": line[25:49].strip(),
                            "print": line[53:56].strip(), "type": line[63:69].strip()})
    return {"lines": [re.sub(r"\b\d{4}/\d{2}/\d{2}\b", "<DATE>", line)
                      for line in lines], "records": records}
