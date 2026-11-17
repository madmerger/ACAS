"""Decode bridge exports and SL070's fixed-column printer output."""

import re


def data_records(content):
    result = {"analysis": [], "suppliers": []}
    for line in content.splitlines():
        fields = line.rstrip().split("|")
        if fields[0] == "A" and len(fields) == 6:
            _, ledger, code, gl, description, reference = fields
            if ledger not in ("P", "S") or not re.fullmatch(r"\d{6}", gl):
                raise ValueError(f"Invalid analysis record: {line!r}")
            result["analysis"].append(dict(ledger=ledger, code=code.rstrip(),
                                           gl=int(gl), description=description,
                                           print=reference))
        elif fields[0] == "P" and len(fields) == 3:
            result["suppliers"].append(dict(code=fields[1].rstrip(), name=fields[2]))
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
