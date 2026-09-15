#!/usr/bin/env python3
"""Check localized screen literals against the English display positions."""

import re
import subprocess
import sys
import unicodedata
from pathlib import Path


BASE_BRANCH = "devin/1789486429-gnucobol-build"
FILES = (
    "ACAS.cbl",
    "general/general.cbl",
    "sales/sales.cbl",
    "purchase/purchase.cbl",
    "stock/stock.cbl",
)
DISPLAY_RE = re.compile(r'^\s*display\s+"([^"]*)"\s+at\s+(\d{4})\b', re.I)
ACCEPT_RE = re.compile(r"^\s*accept\b.*\bat\s+(\d{4})\b", re.I)
PARAGRAPH_RE = re.compile(
    r"^\s*[A-Za-z][A-Za-z0-9-]*(?:\s+section)?\s*\.\s*$", re.I
)


def display_width(text):
    return sum(
        2 if unicodedata.east_asian_width(char) in {"W", "F"} else 1
        for char in text
    )


def screen_items(text):
    displays = []
    accepts = []
    paragraph = ""
    for line_number, line in enumerate(text.splitlines(), 1):
        if line.lstrip().startswith("*>"):
            continue
        if PARAGRAPH_RE.match(line):
            paragraph = line.strip().rstrip(".")
        display = DISPLAY_RE.match(line)
        if display:
            literal, coordinate = display.groups()
            row, column = divmod(int(coordinate), 100)
            displays.append((line_number, row, column, literal, paragraph))
        accept = ACCEPT_RE.match(line)
        if accept:
            coordinate = accept.group(1)
            row, column = divmod(int(coordinate), 100)
            accepts.append((line_number, row, column))
    return displays, accepts


def original_file(path):
    return subprocess.check_output(
        ["git", "show", f"{BASE_BRANCH}:{path}"], text=True
    )


def fail(message):
    print(f"FAIL: {message}")
    return 1


def main():
    errors = 0
    for filename in FILES:
        current_displays, current_accepts = screen_items(Path(filename).read_text())
        original_displays, _ = screen_items(original_file(filename))
        current_boxes = [item for item in current_displays if "[" in item[3]]
        original_boxes = [item for item in original_displays if "[" in item[3]]

        if len(current_boxes) != len(original_boxes):
            errors += fail(
                f"{filename}: display box count changed "
                f"({len(original_boxes)} -> {len(current_boxes)})"
            )
            continue

        for current, original in zip(current_boxes, original_boxes):
            _, current_row, current_column, current_literal, _ = current
            _, original_row, original_column, original_literal, _ = original
            current_box = current_column + display_width(
                current_literal[: current_literal.index("[")]
            )
            original_box = original_column + display_width(
                original_literal[: original_literal.index("[")]
            )
            if (current_row, current_box) != (original_row, original_box):
                errors += fail(
                    f"{filename}:{current[0]}: '[' at "
                    f"({current_row},{current_box}), expected "
                    f"({original_row},{original_box})"
                )
            if not any(row == current_row for _, row, _ in current_accepts):
                errors += fail(
                    f"{filename}:{current[0]}: no ACCEPT on row {current_row}"
                )

        for line_number, row, column, literal, paragraph in current_displays:
            end_column = column + display_width(literal)
            if end_column > 81:
                errors += fail(
                    f"{filename}:{line_number}: literal exceeds 80 columns "
                    f"(ends at {end_column - 1})"
                )
            for (
                other_line,
                other_row,
                other_column,
                other_literal,
                other_paragraph,
            ) in current_displays:
                if (
                    line_number >= other_line
                    or row != other_row
                    or paragraph != other_paragraph
                ):
                    continue
                other_end = other_column + display_width(other_literal)
                if column < other_end and other_column < end_column:
                    errors += fail(
                        f"{filename}:{line_number}: display overlaps "
                        f"{filename}:{other_line} on row {row}"
                    )

    if errors:
        return 1
    print("Japanese display widths and prompt positions are valid.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
