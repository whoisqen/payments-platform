import fnmatch, json, os, re, sys
from pathlib import Path

ROOT = Path(os.environ.get("CLAUDE_PROJECT_DIR") or Path(__file__).resolve().parents[3])
ENVS = ("cde-prod", "prod", "stage", "dev")


def payload():
    try:
        return json.load(sys.stdin)
    except Exception:
        return {}


def init_root(p, path=None):
    # A worktree is its own root: start from the edited file when there is one, else from the payload cwd.
    global ROOT
    start = Path(path).resolve().parent if path else Path(p.get("cwd") or os.getcwd()).resolve()
    for d in (start, *start.parents):
        if (d / ".claude" / "orchestration.yaml").is_file():
            ROOT = d
            return


def agent_of(p):
    return p.get("agent_type") or os.environ.get("CLAUDE_AGENT") or ""


def guarded(fn):
    # A crashing guard must not let the action through (exit 1 is non-blocking).
    try:
        fn()
    except SystemExit:
        raise
    except BaseException as e:
        block(f"hook {Path(sys.argv[0]).name} failed closed: {type(e).__name__}: {e}")


def block(msg):
    print(msg, file=sys.stderr)
    sys.exit(2)


def glob_re(pattern):
    out, i = "", 0
    while i < len(pattern):
        if pattern.startswith("**/", i):
            out += "(?:.*/)?"; i += 3
        elif pattern.startswith("**", i):
            out += ".*"; i += 2
        elif pattern[i] == "*":
            out += "[^/]*"; i += 1
        else:
            out += re.escape(pattern[i]); i += 1
    return re.compile("^" + out + "$")


def matches(rel, patterns):
    return any(glob_re(p).match(rel) for p in patterns)


def orchestration():
    text = (ROOT / ".claude" / "orchestration.yaml").read_text(encoding="utf-8")
    agents, nots = {}, {}
    m = re.search(r"^agents:\n(.*?)^\S", text + "\nx", re.M | re.S)
    for a in re.finditer(r"^  ([\w-]+):\s*\{(.*?)\}", m.group(1) if m else "", re.M | re.S):
        o = re.search(r"owns:\s*\[(.*?)\]", a.group(2), re.S)
        agents[a.group(1)] = re.findall(r'"([^"]+)"', o.group(1)) if o else None
        n = re.search(r"not:\s*\[(.*?)\]", a.group(2), re.S)
        nots[a.group(1)] = re.findall(r'"([^"]+)"', n.group(1)) if n else []
    def lst(key):
        k = re.search(rf"^{key}:\s*\[(.*?)\]", text, re.M | re.S)
        return re.findall(r'"([^"]+)"', k.group(1)) if k else []
    return {"agents": agents, "nots": nots, "humans_only": lst("humans_only"), "ci_only": lst("ci_only"),
            "integrator_only": lst("integrator_only")}


def owned(cfg, agent, r):
    owns = cfg["agents"].get(agent)
    return bool(owns) and matches(r, owns) and not matches(r, cfg["nots"].get(agent, []))


def rel(path):
    p = Path(path)
    if not p.is_absolute():
        p = Path.cwd() / p
    try:
        return p.resolve().relative_to(ROOT.resolve()).as_posix()
    except ValueError:
        return None
