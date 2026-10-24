#!/usr/bin/env python3
"""Build a strictly allowlisted Koha plugin archive using Python's standard library."""
from pathlib import Path
import hashlib
import time
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BASE = "Koha/Plugin/Com/Library/"
FILES = ["MediaManager.pm"] + [
    "MediaManager/" + name for name in (
        "layout.tt", "breadcrumbs.tt", "continue.tt", "configure.tt", "tool.tt", "error.tt", "Security.pm", "Store.pm",
        "Health.pm", "Controller.pm", "openapi.json"
    )
]
target = ROOT / "MediaManager.kpz"
temporary = ROOT / "MediaManager.build.zip"
try:
    with zipfile.ZipFile(temporary, "w", zipfile.ZIP_DEFLATED) as archive:
        for name in sorted(FILES):
            data = (ROOT / BASE / name).read_bytes()
            if not data:
                raise ValueError(f"Empty required file: {name}")
            # Build time, NOT a fixed date: Koha keeps the extracted file times, and Koha's
            # Template Toolkit cache only recompiles a template whose file is newer than its
            # cached copy. A fixed old date makes Koha keep serving stale templates.
            info = zipfile.ZipInfo(BASE + name, time.localtime()[:6])
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, data)
    with zipfile.ZipFile(temporary) as archive:
        assert sorted(archive.namelist()) == sorted(BASE + name for name in FILES)
        assert archive.testzip() is None
    temporary.replace(target)
finally:
    temporary.unlink(missing_ok=True)
print(f"{target.name}: SHA256 {hashlib.sha256(target.read_bytes()).hexdigest()}")
