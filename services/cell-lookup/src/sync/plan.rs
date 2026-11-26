use std::collections::HashMap;

use crate::lookup::hash::LookupKey;
use crate::store::{Item, Route};

#[derive(Clone, Copy, Debug)]
pub struct Limits {
    // Share of the cell's current items one run may delete; guards against a half-read source
    pub max_delete_ratio: f64,
    pub min_deletes: usize,
    pub force: bool,
}

#[derive(Debug, PartialEq, Eq, thiserror::Error)]
pub enum PlanError {
    #[error("source returned no rows while the table holds {0} items for this cell")]
    EmptySource(usize),
    #[error("run would delete {deletes} of {existing} items, above the limit")]
    TooManyDeletes { deletes: usize, existing: usize },
}

#[derive(Default)]
pub struct Plan {
    pub puts: Vec<Item>,
    pub deletes: Vec<LookupKey>,
}

// existing: the items the table holds for this cell
pub fn plan(desired: Vec<Item>, existing: Vec<Item>, limits: Limits) -> Result<Plan, PlanError> {
    if desired.is_empty() && !existing.is_empty() && !limits.force {
        return Err(PlanError::EmptySource(existing.len()));
    }
    let current: HashMap<LookupKey, Route> = existing.into_iter().collect();
    let wanted: HashMap<&LookupKey, &Route> = desired.iter().map(|(k, r)| (k, r)).collect();
    let mut deletes: Vec<LookupKey> = current
        .keys()
        .filter(|k| !wanted.contains_key(k))
        .cloned()
        .collect();
    deletes.sort();
    let limit =
        ((current.len() as f64 * limits.max_delete_ratio).floor() as usize).max(limits.min_deletes);
    if deletes.len() > limit && !limits.force {
        return Err(PlanError::TooManyDeletes {
            deletes: deletes.len(),
            existing: current.len(),
        });
    }
    let puts = desired
        .into_iter()
        .filter(|(k, r)| current.get(k) != Some(r))
        .collect();
    Ok(Plan { puts, deletes })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::store::Kind;

    fn item(h: &str, expires_at: Option<i64>) -> Item {
        (
            LookupKey::hashed(h),
            Route {
                cell: "cell-0".into(),
                merchant_id: "m1".into(),
                kind: Kind::ApiKey,
                expires_at,
            },
        )
    }

    const LIMITS: Limits = Limits {
        max_delete_ratio: 0.5,
        min_deletes: 0,
        force: false,
    };

    #[test]
    fn puts_only_changes_and_deletes_revoked() {
        let existing = vec![item("a", None), item("b", None), item("c", None)];
        let desired = vec![item("a", None), item("b", Some(5)), item("d", None)];
        let p = plan(desired, existing, LIMITS).expect("plan");
        let put_keys: Vec<_> = p.puts.iter().map(|(k, _)| k.as_str().to_owned()).collect();
        assert_eq!(put_keys, vec!["h#b", "h#d"]);
        assert!(p.deletes == vec![LookupKey::hashed("c")]);
    }

    #[test]
    fn refuses_empty_source() {
        let err = plan(vec![], vec![item("a", None)], LIMITS).err();
        assert_eq!(err, Some(PlanError::EmptySource(1)));
    }

    #[test]
    fn refuses_mass_delete_unless_forced() {
        let existing = vec![item("a", None), item("b", None), item("c", None)];
        let desired = vec![item("a", None)];
        assert!(matches!(
            plan(desired.clone(), existing.clone(), LIMITS),
            Err(PlanError::TooManyDeletes {
                deletes: 2,
                existing: 3
            })
        ));
        let forced = Limits {
            force: true,
            ..LIMITS
        };
        assert_eq!(
            plan(desired, existing, forced).expect("plan").deletes.len(),
            2
        );
    }

    #[test]
    fn small_cell_can_revoke_with_default_ratio() {
        let existing = vec![item("a", None), item("b", None), item("c", None)];
        let limits = Limits {
            max_delete_ratio: 0.2,
            min_deletes: 10,
            force: false,
        };
        let p = plan(existing[..2].to_vec(), existing, limits).expect("plan");
        assert_eq!(p.deletes.len(), 1);
    }

    #[test]
    fn first_run_on_empty_table() {
        let p = plan(vec![item("a", None)], vec![], LIMITS).expect("plan");
        assert_eq!(p.puts.len(), 1);
        assert!(p.deletes.is_empty());
    }
}
