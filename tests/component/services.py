import os
import secrets

# Each service runs as a binary from its vendored workspace against the Postgres and Redis of the job.
SPECS = {
    "router": {
        "bin_env": "COMPONENT_ROUTER_BIN", "cwd": "vendor/hyperswitch", "args": ["-f", "config/development.toml"],
        "port": 8080, "health": ["/health", "/health/ready"], "prefix": "ROUTER",
        "env": {
            "ROUTER__SERVER__HOST": "127.0.0.1", "ROUTER__SERVER__PORT": "{port}",
            "ROUTER__MASTER_DATABASE__HOST": "{pg_host}", "ROUTER__MASTER_DATABASE__PORT": "{pg_port}",
            "ROUTER__MASTER_DATABASE__USERNAME": "{pg_user}", "ROUTER__MASTER_DATABASE__PASSWORD": "{pg_password}",
            "ROUTER__MASTER_DATABASE__DBNAME": "{router_db}",
            "ROUTER__REPLICA_DATABASE__HOST": "{pg_host}", "ROUTER__REPLICA_DATABASE__PORT": "{pg_port}",
            "ROUTER__REPLICA_DATABASE__USERNAME": "{pg_user}", "ROUTER__REPLICA_DATABASE__PASSWORD": "{pg_password}",
            "ROUTER__REPLICA_DATABASE__DBNAME": "{router_db}",
            "ROUTER__REDIS__HOST": "{redis_host}", "ROUTER__REDIS__PORT": "{redis_port}",
            "ROUTER__SECRETS__ADMIN_API_KEY": "{admin_key}", "ROUTER__LOCKER__MOCK_LOCKER": "true",
        },
    },
    "drainer": {
        "bin_env": "COMPONENT_DRAINER_BIN", "cwd": "vendor/hyperswitch", "args": ["-f", "config/development.toml"],
        "port": 8081, "health": ["/health", "/health/ready"], "prefix": "DRAINER",
        "env": {
            "DRAINER__SERVER__HOST": "127.0.0.1", "DRAINER__SERVER__PORT": "{port}",
            "DRAINER__MASTER_DATABASE__HOST": "{pg_host}", "DRAINER__MASTER_DATABASE__PORT": "{pg_port}",
            "DRAINER__MASTER_DATABASE__USERNAME": "{pg_user}", "DRAINER__MASTER_DATABASE__PASSWORD": "{pg_password}",
            "DRAINER__MASTER_DATABASE__DBNAME": "{router_db}",
            "DRAINER__REDIS__HOST": "{redis_host}", "DRAINER__REDIS__PORT": "{redis_port}",
        },
    },
    "scheduler": {
        "bin_env": "COMPONENT_SCHEDULER_BIN", "cwd": "vendor/hyperswitch", "args": ["-f", "config/development.toml"],
        "port": 3000, "health": ["/health", "/health/ready"], "prefix": "ROUTER",
        "env": {
            "SCHEDULER_FLOW": "consumer",
            "ROUTER__SCHEDULER__SERVER__HOST": "127.0.0.1", "ROUTER__SCHEDULER__SERVER__PORT": "{port}",
            "ROUTER__MASTER_DATABASE__HOST": "{pg_host}", "ROUTER__MASTER_DATABASE__PORT": "{pg_port}",
            "ROUTER__MASTER_DATABASE__USERNAME": "{pg_user}", "ROUTER__MASTER_DATABASE__PASSWORD": "{pg_password}",
            "ROUTER__MASTER_DATABASE__DBNAME": "{router_db}",
            "ROUTER__REPLICA_DATABASE__HOST": "{pg_host}", "ROUTER__REPLICA_DATABASE__PORT": "{pg_port}",
            "ROUTER__REPLICA_DATABASE__USERNAME": "{pg_user}", "ROUTER__REPLICA_DATABASE__PASSWORD": "{pg_password}",
            "ROUTER__REPLICA_DATABASE__DBNAME": "{router_db}",
            "ROUTER__REDIS__HOST": "{redis_host}", "ROUTER__REDIS__PORT": "{redis_port}",
        },
    },
    "locker": {
        "bin_env": "COMPONENT_LOCKER_BIN", "cwd": "vendor/card-vault", "args": [],
        "port": 3001, "health": ["/health", "/health/diagnostics"], "prefix": "LOCKER",
        "env": {
            "LOCKER__SERVER__HOST": "127.0.0.1", "LOCKER__SERVER__PORT": "{port}",
            "LOCKER__DATABASE__HOST": "{pg_host}", "LOCKER__DATABASE__PORT": "{pg_port}",
            "LOCKER__DATABASE__USERNAME": "{pg_user}", "LOCKER__DATABASE__PASSWORD": "{pg_password}",
            "LOCKER__DATABASE__DBNAME": "{locker_db}",
            "LOCKER__REDIS__HOST": "{redis_host}", "LOCKER__REDIS__PORT": "{redis_port}",
            "LOCKER__TENANT_SECRETS__PUBLIC__MASTER_KEY": "{master_key}",
        },
    },
}


def runtime(environ=None):
    e = os.environ if environ is None else environ
    # keys are generated per run so no key material is stored in the repository
    return {
        "pg_host": e.get("COMPONENT_PG_HOST", "127.0.0.1"), "pg_port": e.get("COMPONENT_PG_PORT", "5432"),
        "pg_user": e.get("COMPONENT_PG_USER", "postgres"), "pg_password": e.get("COMPONENT_PG_PASSWORD", "ci"),
        "router_db": e.get("COMPONENT_ROUTER_DB", "hyperswitch_db"), "locker_db": e.get("COMPONENT_LOCKER_DB", "locker"),
        "redis_host": e.get("COMPONENT_REDIS_HOST", "127.0.0.1"), "redis_port": e.get("COMPONENT_REDIS_PORT", "6379"),
        "admin_key": secrets.token_hex(24), "master_key": secrets.token_hex(32),
    }


def render(name, values):
    spec = SPECS[name]
    ctx = {**values, "port": str(spec["port"])}
    return {k: v.format(**ctx) for k, v in spec["env"].items()}
