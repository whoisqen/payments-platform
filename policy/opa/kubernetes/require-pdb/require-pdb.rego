package kubernetes.require_pdb

# Run with conftest --combine on rendered manifests so the PodDisruptionBudgets of the release are visible next to the workloads.
docs := [d.contents | some d in input]

workloads contains w if {
	some w in docs
	w.kind in {"Deployment", "StatefulSet"}
	w.spec.replicas > 1
}

pdbs contains p if {
	some p in docs
	p.kind == "PodDisruptionBudget"
}

namespace(o) := object.get(o.metadata, "namespace", "default")

selects(pdb, workload) if {
	labels := workload.spec.template.metadata.labels
	every k, v in pdb.spec.selector.matchLabels {
		labels[k] == v
	}
}

covered(w) if {
	some p in pdbs
	namespace(p) == namespace(w)
	selects(p, w)
}

deny contains msg if {
	some w in workloads
	not covered(w)
	msg := sprintf("%v %v has %d replicas and no PodDisruptionBudget selecting its pods", [w.kind, w.metadata.name, w.spec.replicas])
}

# maxUnavailable 0 or minAvailable 100% would block every node drain.
deny contains msg if {
	some p in pdbs
	blocks_drain(p)
	msg := sprintf("PodDisruptionBudget %v blocks node drains", [p.metadata.name])
}

blocks_drain(p) if p.spec.maxUnavailable == 0

blocks_drain(p) if p.spec.maxUnavailable == "0%"

blocks_drain(p) if p.spec.minAvailable == "100%"
