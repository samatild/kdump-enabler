import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "kdump-enabler.sh"


class AzureLinuxTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        source = SCRIPT.read_text()
        source = re.sub(r"/(?:etc|boot|proc|sys|var)/",
                        lambda match: str(self.root) + match.group(), source)
        self.script = self.root / "kdump-enabler.sh"
        self.script.write_text(source)
        self.log = self.root / "commands"

    def write(self, path, text):
        target = self.root / path.lstrip("/")
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
        return target

    def run_shell(self, commands):
        env = dict(os.environ, SCRIPT=str(self.script), LOG=str(self.log))
        return subprocess.run(
            ["bash", "-c", 'source "$SCRIPT"\n' + commands],
            env=env, text=True, capture_output=True,
        )

    def test_detects_azure_linux_and_installs_service_package(self):
        self.write("/etc/os-release", 'ID=azurelinux\nVERSION_ID="4.0"\nNAME="Azure Linux"\n')
        result = self.run_shell(
            'dnf() { printf "%s\\n" "$*" >> "$LOG"; }\n'
            'detect_distro\ninstall_packages\n'
            '[[ "$KDUMP_SERVICE" == kdump ]]'
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("install -y -q kdump-utils kexec-tools makedumpfile grubby",
                      self.log.read_text())

    def test_bls_configuration_is_backed_up_before_grubby(self):
        originals = {
            "/boot/loader/entries/kernel.conf": "options root=UUID=test quiet\n",
            "/etc/default/grub": 'GRUB_ENABLE_BLSCFG=true\n',
            "/boot/grub2/grubenv": "kernelopts=root=UUID=test\n",
            "/etc/kernel/cmdline": "root=UUID=test quiet\n",
        }
        for path, content in originals.items():
            self.write(path, content)
        result = self.run_shell(
            'grubby() { printf "%s\\n" "$*" >> "$LOG"; }\n'
            'configure_azure_crashkernel 384M'
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.log.read_text().strip(),
                         "--update-kernel=ALL --remove-args=crashkernel --args=crashkernel=384M")
        for path, content in originals.items():
            target = self.root / path.lstrip("/")
            backups = (list(target.parent.parent.glob("entries.backup.*/kernel.conf"))
                       if path.endswith("kernel.conf")
                       else list(target.parent.glob(target.name + ".backup.*")))
            self.assertEqual(len(backups), 1, path)
            self.assertEqual(backups[0].read_text(), content)

    def test_missing_bls_entries_fails_without_calling_grubby(self):
        result = self.run_shell(
            'grubby() { echo called >> "$LOG"; }\n'
            'configure_azure_crashkernel 384M'
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("requires grubby and BLS entries", result.stdout)
        self.assertFalse(self.log.exists())

    def test_does_not_start_service_without_reserved_memory(self):
        self.write("/sys/kernel/kexec_crash_size", "0\n")
        self.write("/proc/cmdline", "root=UUID=test crashkernel=384M\n")
        result = self.run_shell(
            'systemctl() { printf "%s\\n" "$*" >> "$LOG"; }\n'
            'DISTRO=azurelinux\nKDUMP_SERVICE=kdump\nenable_kdump_service'
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.log.read_text().strip(), "enable kdump.service")

    def test_status_requires_loaded_capture_kernel(self):
        self.write("/proc/cmdline", "crashkernel=384M\n")
        self.write("/proc/sys/kernel/sysrq", "1\n")
        loaded = self.write("/sys/kernel/kexec_crash_loaded", "0\n")
        commands = ("systemctl() { return 0; }\nDISTRO=azurelinux\n"
                    "KDUMP_SERVICE=kdump\ncheck_kdump_status")
        result = self.run_shell(commands)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        loaded.write_text("1\n")
        result = self.run_shell(commands)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
