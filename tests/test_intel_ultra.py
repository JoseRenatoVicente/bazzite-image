import os
from pathlib import Path
import re
import subprocess
import tempfile
import tomllib
import unittest


ROOT = Path(__file__).resolve().parents[1]
HOOK = ROOT / "system_files/usr/lib/systemd/system-sleep/latitude-lpss-s4.sh"


class ImageDefaultsTest(unittest.TestCase):
    def test_gpu_selection_is_limited_to_the_host_gpu(self):
        path = ROOT / "system_files/usr/lib/bootc/kargs.d/20-intel-meteor-lake.toml"
        config = tomllib.loads(path.read_text())
        self.assertEqual(config["match-architectures"], ["x86_64"])
        self.assertEqual(
            config["kargs"], ["i915.force_probe=7d45", "xe.force_probe=!7d45"]
        )

    def test_compute_dependencies_are_not_removed(self):
        script = (ROOT / "build_files/build.sh").read_text()
        patterns = script.split("REMOVE_PATTERNS=(", 1)[1].split("\n)", 1)[0]
        removed = {line.strip() for line in patterns.splitlines()}
        for package in (
            "intel-compute-runtime",
            "intel-opencl",
            "intel-level-zero",
            "intel-opencl-clang",
            "intel-igc",
            "intel-igc-libs",
            "clang-libs",
            "spirv-llvm-translator",
        ):
            with self.subTest(package=package):
                self.assertNotIn(package, removed)

    def test_hibernation_does_not_change_lid_action_by_default(self):
        system_files = ROOT / "system_files"
        for base in ("usr/lib", "etc"):
            self.assertFalse((system_files / base / "systemd/logind.conf.d").exists())
        self.assertFalse(
            (system_files / "etc/bazzite-image/latitude-lpss-s4-workaround").exists()
        )

    def test_dracut_preserves_ostree_and_resume(self):
        path = ROOT / "system_files/usr/lib/dracut/dracut.conf.d/30-intel-meteor-lake.conf"
        modules = re.findall(r'add_dracutmodules\+="([^"]*)"', path.read_text())
        enabled = " ".join(modules).split()
        self.assertIn("ostree", enabled)
        self.assertIn("resume", enabled)


class InitramfsBuildTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "tmp").mkdir()
        (self.root / "var").mkdir()
        (self.root / "root").symlink_to("var/roothome", target_is_directory=True)
        self.kernel = self.root / "usr/lib/modules/image-kernel"
        self.kernel.mkdir(parents=True)
        (self.kernel / "vmlinuz").touch()
        hook = self.root / "usr/lib/systemd/system-sleep/latitude-lpss-s4.sh"
        hook.parent.mkdir(parents=True)
        hook.touch()

        # Mock package tools and dracut. No package transaction or real
        # initramfs generation is allowed on the machine running these tests.
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for command in ("dnf5", "rpm", "modinfo"):
            self.mock(command, "exit 0\n")
        self.mock("dracut", '''
[[ "$DRACUT_NO_XATTR" == 1 ]] || exit 1
[[ -d "$TEST_ROOT/var/roothome" ]] || exit 1
printf 'test initramfs' > "${@: -1}"
printf '%s\\n' "${TEST_DRACUT_ERROR:-}"
exit 0
''')
        self.mock("lsinitrd", '''
if [[ "$1" == --mod ]]; then
    for module in ostree resume; do
        [[ "$module" == "${TEST_MISSING_MODULE:-}" ]] && continue
        printf '%s\\n' "$module"
    done
    exit 0
fi
for driver in i915 thunderbolt dm_snapshot; do
    [[ "$driver" == "${TEST_MISSING_DRIVER:-}" ]] && continue
    printf 'rd.driver.pre=%s\\n' "$driver"
done
exit 0
''')
        script = (ROOT / "build_files/intel-ultra.sh").read_text()
        script = re.sub(
            r"/(?:usr/lib|tmp)/|/root\b|/var/roothome\b",
            lambda match: str(self.root) + match[0],
            script,
        )
        self.script = self.root / "build.sh"
        self.script.write_text(script)

    def mock(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/bash\n" + body)
        path.chmod(0o755)

    def run_build(self, **overrides):
        env = {
            "PATH": str(self.bin) + os.pathsep + os.environ["PATH"],
            "TEST_ROOT": str(self.root),
        }
        env.update(overrides)
        return subprocess.run(
            ["bash", str(self.script)], env=env, capture_output=True, text=True
        )

    def test_build_uses_image_kernel_and_disables_xattr_copy(self):
        result = self.run_build()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.kernel / "initramfs.img").is_file())
        self.assertTrue((self.root / "root").is_symlink())
        self.assertFalse((self.root / "var/roothome").exists())

    def test_zero_exit_from_dracut_does_not_hide_install_errors(self):
        for error in ("dracut[E]: FAILED: test", "dracut-install: ERROR: test"):
            with self.subTest(error=error):
                result = self.run_build(TEST_DRACUT_ERROR=error)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("initramfs generation reported errors", result.stderr)
                self.assertFalse((self.root / "var/roothome").exists())

    def test_existing_root_home_is_preserved(self):
        home = self.root / "var/roothome"
        home.mkdir()
        sentinel = home / "existing-file"
        sentinel.write_text("preserve me")
        result = self.run_build()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(sentinel.read_text(), "preserve me")

    def test_missing_early_driver_fails_the_build(self):
        result = self.run_build(TEST_MISSING_DRIVER="i915")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("initramfs does not preload i915", result.stderr)

    def test_missing_boot_module_fails_the_build(self):
        for module in ("ostree", "resume"):
            with self.subTest(module=module):
                result = self.run_build(TEST_MISSING_MODULE=module)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(f"initramfs is missing {module} support", result.stderr)

    def test_missing_image_kernel_fails_the_build(self):
        (self.kernel / "vmlinuz").unlink()
        result = self.run_build()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no bootable image kernel", result.stderr)


class LpssSleepHookTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

        # Redirect only the hook's filesystem roots into fixtures. Never run an
        # enabled hook against the test machine's real sysfs, /etc or /run.
        script = HOOK.read_text()
        script = re.sub(
            r"/(?:sys|etc|run)/", lambda match: str(self.root) + match[0], script
        )
        self.hook = self.root / "hook.sh"
        self.hook.write_text(script)

        self.opt_in = self.root / "etc/bazzite-image/latitude-lpss-s4-workaround"
        self.opt_in.parent.mkdir(parents=True)
        self.opt_in.touch()
        self.state = self.root / "run/latitude-lpss-s4-unbound"
        self.state.parent.mkdir()
        self.dmi = self.root / "sys/class/dmi/id"
        self.dmi.mkdir(parents=True)
        (self.dmi / "sys_vendor").write_text("Dell Inc.\n")
        (self.dmi / "product_name").write_text("Latitude 5450\n")
        self.pci = self.root / "sys/bus/pci/devices/0000:00:15.3"
        self.pci.mkdir(parents=True)
        (self.pci / "vendor").write_text("0x8086\n")
        (self.pci / "device").write_text("0x7e7b\n")
        self.driver = self.root / "sys/bus/pci/drivers/intel-lpss"
        self.driver.mkdir(parents=True)
        (self.driver / "bind").touch()
        (self.driver / "unbind").touch()
        (self.pci / "driver").symlink_to(self.driver, target_is_directory=True)

    def run_hook(self, phase="pre", operation="hibernate", action=None):
        env = {"PATH": os.environ["PATH"]}
        if action is not None:
            env["SYSTEMD_SLEEP_ACTION"] = action
        subprocess.run(
            ["bash", str(self.hook), phase, operation],
            env=env,
            check=True,
            capture_output=True,
            text=True,
        )

    def assert_untouched(self):
        self.assertEqual((self.driver / "unbind").read_text(), "")
        self.assertEqual((self.driver / "bind").read_text(), "")
        self.assertFalse(self.state.exists())

    def test_disabled_by_default(self):
        self.opt_in.unlink()
        self.run_hook()
        self.assert_untouched()

    def test_wrong_or_missing_hardware_is_untouched(self):
        for relative in (
            "sys/class/dmi/id/sys_vendor",
            "sys/class/dmi/id/product_name",
            "sys/bus/pci/devices/0000:00:15.3/vendor",
            "sys/bus/pci/devices/0000:00:15.3/device",
        ):
            path = self.root / relative
            original = path.read_text()
            with self.subTest(path=relative, case="wrong"):
                path.write_text("other\n")
                self.run_hook()
                self.assert_untouched()
            with self.subTest(path=relative, case="missing"):
                path.unlink()
                self.run_hook()
                self.assert_untouched()
            path.write_text(original)

    def test_suspend_stages_do_not_unbind(self):
        for action in ("suspend", "suspend-after-failed-hibernate", ""):
            with self.subTest(action=action):
                self.run_hook(operation="suspend-then-hibernate", action=action)
                self.assert_untouched()
        self.run_hook(operation="suspend")
        self.assert_untouched()

    def test_both_latitude_models_can_opt_in(self):
        for model in ("Latitude 5450", "Latitude 7450"):
            with self.subTest(model=model):
                (self.dmi / "product_name").write_text(model + "\n")
                self.run_hook()
                self.assertEqual(
                    (self.driver / "unbind").read_text(), "0000:00:15.3\n"
                )
                self.assertTrue(self.state.exists())
                self.state.unlink()
                (self.driver / "unbind").write_text("")

    def test_hibernate_stage_of_suspend_then_hibernate_unbinds(self):
        self.run_hook(operation="suspend-then-hibernate", action="hibernate")
        self.assertEqual((self.driver / "unbind").read_text(), "0000:00:15.3\n")
        self.assertTrue(self.state.exists())

    def test_hybrid_sleep_unbinds(self):
        self.run_hook(operation="hybrid-sleep")
        self.assertTrue(self.state.exists())

    def test_foreign_driver_is_untouched(self):
        (self.pci / "driver").unlink()
        (self.pci / "driver").symlink_to(self.root, target_is_directory=True)
        self.run_hook()
        self.assert_untouched()

    def test_resume_without_our_unbind_is_untouched(self):
        self.run_hook(phase="post")
        self.assert_untouched()

    def test_resume_rebinds_only_our_unbound_device(self):
        self.run_hook(operation="suspend-then-hibernate", action="hibernate")
        # A fixture file cannot perform sysfs's implicit unlink on unbind.
        (self.pci / "driver").unlink()
        self.run_hook("post", "suspend-then-hibernate", "hibernate")
        self.assertEqual((self.driver / "bind").read_text(), "0000:00:15.3\n")
        self.assertFalse(self.state.exists())

    def test_resume_does_not_bind_twice(self):
        self.run_hook()
        self.run_hook(phase="post")
        self.assertEqual((self.driver / "bind").read_text(), "")
        self.assertFalse(self.state.exists())


if __name__ == "__main__":
    unittest.main()
