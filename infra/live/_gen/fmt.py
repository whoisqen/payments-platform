#!/usr/bin/env python3
"""Run terraform fmt on every .hcl file of infra/live through .tf copies; --check only reports."""
import os, shutil, subprocess, sys, tempfile

ROOT = "/data/vlad/portfolio/payments-platform/.claude/worktrees/agent-ae6ce5dd4f5691ab7/infra/live"
check = "--check" in sys.argv
files = []
for d, dirs, fs in os.walk(ROOT):
    dirs[:] = [x for x in dirs if x != "_gen"]
    files += [os.path.join(d, f) for f in fs if f.endswith(".hcl")]
tmp = tempfile.mkdtemp(dir="/data/vlad/tmp")
m = {}
for i, f in enumerate(sorted(files)):
    t = os.path.join(tmp, f"f{i}.tf")
    shutil.copy(f, t)
    m[t] = f
cmd = ["terraform", "fmt", "-check", "-diff"] if check else ["terraform", "fmt"]
r = subprocess.run(cmd + [tmp], capture_output=True, text=True)
print(r.stdout[:3000], r.stderr[:2000])
if not check:
    for t, f in m.items():
        shutil.copy(t, f)
print(len(files), "files", "exit", r.returncode)
shutil.rmtree(tmp)
sys.exit(r.returncode)
