from pathlib import Path
text = Path(r"c:\Test House BE200 control\_write_orchestrate.py").read_text(encoding="utf-8")
exec(text)
