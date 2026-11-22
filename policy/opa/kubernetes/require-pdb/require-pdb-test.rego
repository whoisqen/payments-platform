package kubernetes.require_pdb_test

import data.kubernetes.require_pdb

workload(kind, name, namespace, replicas, labels) := {"contents": {
	"kind": kind,
	"metadata": {"name": name, "namespace": namespace},
	"spec": {"replicas": replicas, "template": {"metadata": {"labels": labels}}},
}}

pdb(name, namespace, spec) := {"contents": {
	"kind": "PodDisruptionBudget",
	"metadata": {"name": name, "namespace": namespace},
	"spec": spec,
}}

router := workload("Deployment", "router", "payments", 3, {"app": "router"})

router_pdb := pdb("router", "payments", {"maxUnavailable": 1, "selector": {"matchLabels": {"app": "router"}}})

test_workload_with_pdb_allowed if {
	count(require_pdb.deny) == 0 with input as [router, router_pdb]
}

test_workload_without_pdb_denied if {
	count(require_pdb.deny) == 1 with input as [router]
}

test_pdb_in_other_namespace_denied if {
	other := pdb("router", "staging", {"maxUnavailable": 1, "selector": {"matchLabels": {"app": "router"}}})
	count(require_pdb.deny) == 1 with input as [router, other]
}

test_pdb_with_other_selector_denied if {
	other := pdb("drainer", "payments", {"maxUnavailable": 1, "selector": {"matchLabels": {"app": "drainer"}}})
	count(require_pdb.deny) == 1 with input as [router, other]
}

test_single_replica_needs_no_pdb if {
	count(require_pdb.deny) == 0 with input as [workload("Deployment", "tool", "payments", 1, {"app": "tool"})]
}

test_statefulset_without_pdb_denied if {
	count(require_pdb.deny) == 1 with input as [workload("StatefulSet", "vault", "shared", 3, {"app": "vault"})]
}

test_pdb_blocking_drains_denied if {
	blocking := pdb("router", "payments", {"maxUnavailable": 0, "selector": {"matchLabels": {"app": "router"}}})
	count(require_pdb.deny) == 1 with input as [router, blocking]
}

test_pdb_requiring_all_pods_denied if {
	blocking := pdb("router", "payments", {"minAvailable": "100%", "selector": {"matchLabels": {"app": "router"}}})
	count(require_pdb.deny) == 1 with input as [router, blocking]
}
