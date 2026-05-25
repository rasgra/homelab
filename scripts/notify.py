import importlib.machinery
import importlib.util
from pathlib import Path

_path = Path(__file__).resolve().parent / "notify"
_loader = importlib.machinery.SourceFileLoader("notify_impl", str(_path))
_spec = importlib.util.spec_from_loader("notify_impl", _loader)
_mod = importlib.util.module_from_spec(_spec)
_loader.exec_module(_mod)

send = _mod.send
Level = _mod.Level
