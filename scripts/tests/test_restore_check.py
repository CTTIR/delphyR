"""Recovery transport tests; no PostgreSQL or Docker server is started."""
import ast
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import types
import unittest
from unittest.mock import Mock

SCRIPT = Path(__file__).resolve().parents[1] / "restore-check.sh"
CODE = SCRIPT.read_text().split("<<'PYTHON'\n", 1)[1].rsplit("\nPYTHON", 1)[0]
FUNCTIONS = ast.Module(body=[node for node in ast.parse(CODE).body if isinstance(node, ast.FunctionDef)], type_ignores=[])


class RecoveryTransportTests(unittest.TestCase):
    def environment(self, root, backend="native"):
        commands = []
        environment = dict(
            backend=backend, source="delphyr-dev-postgres", name="owned-restore-test",
            database="delphyr", source_database="delphyr_audit", source_port="55439", source_user="postgres",
            pg_bin=Path("/supplied pg/bin"), socket=root / "socket", restore_data=root / "pgdata", out=root,
            image="sha256:synthetic", shlex=shlex, shutil=shutil, time=types.SimpleNamespace(sleep=Mock()),
            os=__import__("os"), subprocess=types.SimpleNamespace(
                run=Mock(return_value=types.SimpleNamespace(returncode=0, stdout="true\n")), DEVNULL=subprocess.DEVNULL),
        )
        exec(compile(FUNCTIONS, str(SCRIPT), "exec"), environment)
        environment["run"] = lambda args, **kwargs: commands.append(args)
        return environment, commands

    def test_native_source_is_loopback_and_restore_is_private_socket(self):
        with tempfile.TemporaryDirectory() as directory:
            env, calls = self.environment(Path(directory))
            source = env["client"](env["source"], "pg_dump", "--snapshot=0001-1")
            target = env["client"](env["name"], "pg_restore", "--single-transaction")
            self.assertEqual(source[:2], ["/supplied pg/bin/pg_dump", "--snapshot=0001-1"])
            self.assertEqual(source[source.index("-h") + 1], "127.0.0.1")
            self.assertEqual(source[source.index("-d") + 1], "delphyr_audit")
            self.assertEqual(target[target.index("-h") + 1], str(env["socket"]))
            self.assertEqual(target[target.index("-d") + 1], "delphyr")
            env["start_restore"]()
            startup = next(call for call in calls if Path(call[0]).name == "pg_ctl")
            options = shlex.split(startup[startup.index("-o") + 1])
            self.assertIn("listen_addresses=", options)
            self.assertIn("unix_socket_directories=" + str(env["socket"]), options)
            self.assertEqual(calls[0][calls[0].index("-D") + 1], str(env["restore_data"]))

    def test_cleanup_never_removes_a_cluster_that_did_not_stop(self):
        with tempfile.TemporaryDirectory() as directory:
            env, calls = self.environment(Path(directory))
            env["restore_data"].mkdir()
            env["socket"].mkdir()
            (env["restore_data"] / "postmaster.pid").write_text("owned fixture")
            env["run"] = Mock(side_effect=subprocess.CalledProcessError(1, "pg_ctl"))
            with self.assertRaises(subprocess.CalledProcessError):
                env["cleanup_restore"]()
            self.assertTrue(env["restore_data"].is_dir())
            self.assertTrue(env["socket"].is_dir())

    def test_source_and_target_fingerprints_use_the_same_timezone(self):
        with tempfile.TemporaryDirectory() as directory:
            env, _ = self.environment(Path(directory))
            env["run"] = Mock(return_value=types.SimpleNamespace(stdout="table|1|same-hash\n"))
            query = "BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY; SELECT to_jsonb(t) FROM research.rounds t; COMMIT;\n"
            for target in (env["source"], env["name"]):
                self.assertEqual(env["psql"](target, query), "table|1|same-hash\n")
                sent = env["run"].call_args.kwargs["input"]
                self.assertEqual(sent, "SET TIME ZONE 'UTC';\n" + query)

    def test_successful_native_cleanup_removes_only_owned_runtime_directories(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            env, calls = self.environment(root)
            env["restore_data"].mkdir()
            env["socket"].mkdir()
            (root / "database.dump").write_bytes(b"retained backup")
            env["cleanup_restore"]()
            self.assertFalse(env["restore_data"].exists())
            self.assertFalse(env["socket"].exists())
            self.assertEqual((root / "database.dump").read_bytes(), b"retained backup")
            self.assertEqual(calls[0][calls[0].index("-D") + 1], str(env["restore_data"]))

    def test_socket_path_is_short_private_and_independent_of_checkout_length(self):
        node = next(node for node in ast.parse(CODE).body if isinstance(node, ast.Assign)
                    and any(isinstance(target, ast.Name) and target.id == "socket" for target in node.targets))
        env = {"Path": Path, "tempfile": tempfile, "out": Path("/tmp") / ("very-long-checkout-" * 20)}
        exec(compile(ast.Module(body=[node], type_ignores=[]), str(SCRIPT), "exec"), env)
        try:
            self.assertLess(len(bytes(env["socket"] / ".s.PGSQL.5432")), 100)
            self.assertEqual(env["socket"].stat().st_mode & 0o777, 0o700)
        finally:
            shutil.rmtree(env["socket"])

    def test_docker_restore_retains_no_network(self):
        with tempfile.TemporaryDirectory() as directory:
            env, calls = self.environment(Path(directory), backend="docker")
            env["start_restore"]()
            self.assertIn("--network=none", calls[0])
            self.assertNotIn("-p", calls[0])
            self.assertNotIn("--publish", calls[0])

    def test_connection_string_cannot_override_the_native_loopback_source(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "scripts").mkdir()
            copied = root / "scripts" / SCRIPT.name
            shutil.copy2(SCRIPT, copied)
            for database in ("postgresql://remote.example/delphyr", "host=remote.example dbname=delphyr"):
                env = {"PATH": __import__("os").environ["PATH"], "DELPHYR_RESTORE_BACKEND": "native",
                       "DELPHYR_PG_BIN": "/unused", "DELPHYR_RESTORE_SOURCE_PORT": "55439", "DELPHYR_RESTORE_SOURCE_DB": database}
                result = subprocess.run(["bash", str(copied)], env=env, text=True, capture_output=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("plain database name", result.stderr)
                self.assertFalse((root / ".checks").exists())

    @unittest.skipUnless(sys.platform == "darwin", "macOS fail-fast boundary")
    def test_docker_mode_on_macos_fails_before_creating_backup_or_starting_docker(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "scripts").mkdir()
            copied = root / "scripts" / SCRIPT.name
            shutil.copy2(SCRIPT, copied)
            result = subprocess.run(["bash", str(copied)], env={"PATH": __import__("os").environ["PATH"], "DELPHYR_RESTORE_BACKEND": "docker"}, text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("DELPHYR_RESTORE_BACKEND=native", result.stderr)
            self.assertFalse((root / ".checks").exists())


if __name__ == "__main__":
    unittest.main()
