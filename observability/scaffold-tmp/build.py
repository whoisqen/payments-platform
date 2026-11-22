import importlib
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common

for mod in sys.argv[1:]:
    importlib.import_module(mod)
common.emit()
print(len(common.ALL), "alerts")
