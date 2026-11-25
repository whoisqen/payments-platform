"""Admin AI agent: analysis of logs, metrics, alerts and cluster state through Bedrock; every byte to the model is sanitised and compressed."""
import sys
from pathlib import Path

# reuse tools/ai/sanitize.py as the one redaction implementation
_AI = str(Path(__file__).resolve().parents[1])
if _AI not in sys.path:
    sys.path.insert(0, _AI)
