
#!/usr/bin/env python3
import csv
import io
import time
from pathlib import Path

LOG_DIR = Path("/tmp/mangohud")
OUTPUT = Path("/tmp/quickshell_fps.txt")
POLL_INTERVAL = 0.1
STALE_SECONDS = 2.0


def write_fps(value):
    try:
        tmp = OUTPUT.with_suffix(".tmp")
        tmp.write_text(f"{value}\n")
        tmp.replace(OUTPUT)
    except OSError:
        pass


def latest_fps(path):
    try:
        content = path.read_text(errors="replace")
        rows = list(csv.reader(io.StringIO(content)))
    except (OSError, csv.Error):
        return None

    header = None
    for i, row in enumerate(rows):
        if "fps" in row and "elapsed" in row:
            header = (i, row)
            break

    if header is None:
        return None

    header_index, columns = header
    fps_index = columns.index("fps")

    for row in reversed(rows[header_index + 1:]):
        if len(row) <= fps_index:
            continue
        try:
            fps = float(row[fps_index])
            if fps >= 0:
                return round(fps)
        except ValueError:
            continue

    return None


def main():
    last_value = None

    while True:
        value = 0
        try:
            files = [
                p for p in LOG_DIR.glob("*.csv")
                if not p.stem.endswith("_summary")
            ]

            if files:
                newest = max(files, key=lambda p: p.stat().st_mtime)
                age = time.time() - newest.stat().st_mtime

                if age <= STALE_SECONDS:
                    result = latest_fps(newest)
                    if result is not None:
                        value = result
        except OSError:
            pass

        if value != last_value:
            write_fps(value)
            last_value = value

        time.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        write_fps(0)
