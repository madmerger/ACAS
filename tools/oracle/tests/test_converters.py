import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from converters import data_records, report_json
from runner import HERE, load, seed


def test_data_records():
    result = data_records(f"ASa 000000{'Sales group':24}\n"
                          f"APa1200100{'Purchase materials':24}MAT\n"
                          "PSUP0001Oracle Supplier\n")
    assert result["analysis"] == [
        dict(ledger="S", code="a", gl=0, description="Sales group", print=""),
        dict(ledger="P", code="a1", gl=200100, description="Purchase materials", print="MAT")]
    assert result["suppliers"] == [dict(code="SUP0001", name="Oracle Supplier")]


def test_empty_data():
    assert data_records("") == {"analysis": [], "suppliers": []}


@pytest.mark.parametrize("content", ["bad", "ASa1oops!!name", "AXa1000001name",
                                     "Pkey", "ASa1000001" + "x" * 28])
def test_invalid_data(content):
    with pytest.raises(ValueError):
        data_records(content)


def test_screen_enterable_delimiters_in_export():
    description = "Goods | services \\"
    result = data_records(f"ASa1000001{description:24}|\\|\n"
                          f"PSUP0001{description}\n")
    assert result["analysis"][0]["description"] == description
    assert result["analysis"][0]["print"] == "|\\|"
    assert result["suppliers"][0]["name"] == description


def test_report():
    row = " P   a1     002001       Purchase materials          MAT       Detail"
    result = report_json("Product Analysis Codes\nOracle Company 2020/01/02\n\f" + row)
    assert result["records"] == [dict(ledger="P", code="a1", gl=2001,
                                      description="Purchase materials", print="MAT", type="Detail")]
    assert result["lines"][1] == "Oracle Company <DATE>"


def test_empty_report():
    assert report_json("\n\f ") == {"lines": [], "records": []}


def test_bad_report():
    with pytest.raises(ValueError, match="Not an SL070"):
        report_json("unrelated report")
    with pytest.raises(ValueError):
        report_json("Product Analysis Codes\n"
                    " P   a1     BADGL!       Purchase materials          MAT       Detail")


def test_golden_contains_created_record_and_report():
    golden = load(HERE / "golden/SL-ANALYSIS-001.json")
    assert golden["data"]["analysis"][-1] == dict(ledger="S", code="b", gl=0,
                                                   description="Oracle service", print="SVC")
    assert len(golden["reports"]["prt-1"]["records"]) == 5
    assert golden["reports"]["prt-1"]["records"][-1]["description"] == "Oracle service"


def test_fixture_rejects_truncation_and_delimiters(tmp_path):
    fixture = load(HERE / "fixture.json")
    fixture["analysis"][0]["description"] = "x" * 25
    with pytest.raises(ValueError, match="Fixture field"):
        seed(tmp_path, None, fixture, {})
    fixture = {"analysis": [], "suppliers": [{"code": "BAD|KEY", "name": "Test"}]}
    with pytest.raises(ValueError, match="supplier"):
        seed(tmp_path, None, fixture, {})
