# kdump-enabler

A Bash script that automatically enables and configures kdump across multiple Linux distributions. It handles package installation, service activation, and basic setup, ensuring systems are ready to collect kernel crash dumps for later analysis.

## Features

- **Multi-distribution support**: Works with Ubuntu, Debian, RHEL, CentOS, Fedora, openSUSE, and Arch Linux
- **Automatic package installation**: Installs required kdump tools
- **Intelligent crashkernel sizing**: Automatically determines appropriate memory allocation based on system RAM
- **GRUB configuration**: Updates bootloader configuration with crashkernel parameter
- **Service management**: Enables and starts kdump service automatically
- **SysRq enablement**: Configures kernel SysRq for manual crash triggering
- **Status checking**: Verify current kdump configuration before making changes
- **Safe configuration**: Creates backups of modified files before changes

## Requirements

- Root privileges (run with `sudo`)
- systemd-based Linux distribution
- GRUB bootloader
- Sufficient disk space in `/var/crash` for crash dumps

## Supported Distributions

| Distribution | Package Manager | Tested |
|-------------|----------------|--------|
| Ubuntu | apt | ✓ |
| Debian | apt | ✓ |
| Pop!_OS | apt | ✓ |
| RHEL | yum | ✓ |
| CentOS | yum | ✓ |
| Rocky Linux | yum | ✓ |
| AlmaLinux | yum | ✓ |
| Fedora | dnf | ✓ |
| openSUSE | zypper | ✓ |
| SLES | zypper | ✓ |
| Arch Linux | pacman | ✓ |
| Manjaro | pacman | ✓ |

## Installation

Clone the repository and run the script:

```bash
git clone https://github.com/yourusername/kdump-enabler.git
cd kdump-enabler
sudo ./kdump-enabler.sh
```

Or download and run directly:

```bash
curl -O https://raw.githubusercontent.com/yourusername/kdump-enabler/main/kdump-enabler.sh
chmod +x kdump-enabler.sh
sudo ./kdump-enabler.sh
```

## Usage

### Basic Usage

Run the script with sudo to interactively configure kdump:

```bash
sudo ./kdump-enabler.sh
```

### Command-Line Options

```
OPTIONS:
    -h, --help          Show help message
    -v, --version       Show version information
    -y, --yes           Skip confirmation prompts (non-interactive mode)
    --no-sysrq          Skip sysrq crash enablement
    --check-only        Only check current configuration without making changes
```

### Examples

**Interactive mode with confirmation prompts:**
```bash
sudo ./kdump-enabler.sh
```

**Non-interactive mode (useful for automation):**
```bash
sudo ./kdump-enabler.sh -y
```

**Check current kdump status without making changes:**
```bash
sudo ./kdump-enabler.sh --check-only
```

**Configure kdump without enabling SysRq:**
```bash
sudo ./kdump-enabler.sh --no-sysrq
```

## What the Script Does

1. **Detects your Linux distribution** and determines the appropriate package manager
2. **Checks current kdump status** and reports existing configuration
3. **Installs required packages**:
   - Ubuntu/Debian: `linux-crashdump`, `kdump-tools`, `kexec-tools`
   - RHEL/CentOS/Fedora: `kexec-tools`
   - openSUSE/SLES: `kdump`
   - Arch/Manjaro: `kexec-tools`
4. **Configures crashkernel parameter** in GRUB based on system RAM:
   - < 8GB RAM: 256M reserved for crash kernel
   - 8-16GB RAM: 384M reserved
   - \> 16GB RAM: 512M reserved
5. **Enables kdump service** at boot and starts it
6. **Enables SysRq** for manual crash triggering
7. **Creates crash dump directory** at `/var/crash`

## Post-Installation

### Reboot Required

After running the script, **you must reboot your system** for the crashkernel parameter to take effect:

```bash
sudo reboot
```

### Verify Configuration

After reboot, verify that kdump is working correctly:

**Ubuntu/Debian:**
```bash
sudo kdump-tools test
sudo systemctl status kdump-tools
```

**RHEL/CentOS/Fedora:**
```bash
sudo kdumpctl showmem
sudo systemctl status kdump
```

**Check if crashkernel is loaded:**
```bash
cat /proc/cmdline | grep crashkernel
```

**Check SysRq status:**
```bash
cat /proc/sys/kernel/sysrq
# Should output: 1
```

## Testing Crash Dumps

### ⚠️ WARNING: Testing Will Reboot Your System!

To trigger a test crash and verify that kdump is working:

```bash
# This will immediately crash the system and generate a dump
echo c | sudo tee /proc/sysrq-trigger
```

After the system reboots, check for the crash dump:

```bash
ls -lh /var/crash/
```

## Troubleshooting

### kdump service fails to start

- **Check if crashkernel is loaded**: `cat /proc/cmdline | grep crashkernel`
- **Verify you've rebooted** after running the script
- **Check available memory**: kdump requires reserved memory at boot time
- **View service logs**: `sudo journalctl -u kdump -xe`

### crashkernel parameter not in kernel command line

- Ensure you've rebooted after running the script
- Check GRUB configuration: `/etc/default/grub`
- Manually update GRUB:
  - Ubuntu/Debian: `sudo update-grub`
  - RHEL/Fedora: `sudo grub2-mkconfig -o /boot/grub2/grub.cfg`

### Insufficient memory for crashkernel

If your system has limited RAM, you may need to reduce the crashkernel size:

Edit `/etc/default/grub` and modify the `crashkernel=` parameter:
```bash
# For systems with < 2GB RAM
crashkernel=128M
```

Then update GRUB and reboot.

### Crash dumps not being generated

1. Verify kdump service is running: `sudo systemctl status kdump`
2. Check disk space in `/var/crash`
3. Review kdump configuration:
   - Ubuntu/Debian: `/etc/default/kdump-tools`
   - RHEL/Fedora: `/etc/kdump.conf`
4. Test with SysRq trigger: `echo c | sudo tee /proc/sysrq-trigger`

## Configuration Files

The script creates or modifies the following files:

- `/etc/default/grub` - GRUB bootloader configuration (backed up before changes)
- `/etc/default/kdump-tools` - Ubuntu/Debian kdump configuration
- `/etc/kdump.conf` - RHEL/Fedora/openSUSE kdump configuration
- `/etc/sysctl.conf` or `/etc/sysctl.d/99-kdump-sysrq.conf` - SysRq configuration
- `/var/crash/` - Crash dump storage directory

Backup files are created with timestamps (e.g., `grub.backup.20250110_143022`) before any modifications.

## Uninstallation

To disable kdump:

1. **Stop and disable the service:**
   ```bash
   sudo systemctl stop kdump
   sudo systemctl disable kdump
   ```

2. **Remove crashkernel from GRUB:**
   Edit `/etc/default/grub` and remove the `crashkernel=` parameter, then:
   ```bash
   # Ubuntu/Debian
   sudo update-grub
   
   # RHEL/Fedora
   sudo grub2-mkconfig -o /boot/grub2/grub.cfg
   ```

3. **Reboot the system**

4. **Optionally remove packages:**
   ```bash
   # Ubuntu/Debian
   sudo apt-get remove linux-crashdump kdump-tools kexec-tools
   
   # RHEL/CentOS/Fedora
   sudo dnf remove kexec-tools
   ```

## Security Considerations

- Crash dumps may contain sensitive information from kernel memory
- Secure the `/var/crash` directory with appropriate permissions
- Consider encrypting crash dumps for sensitive environments
- Review and clean old crash dumps regularly

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

### Development

To test the script:

1. Fork the repository
2. Create a feature branch
3. Test on your target distribution
4. Submit a pull request

### Testing Checklist

- [ ] Script runs without errors
- [ ] Packages are installed correctly
- [ ] GRUB configuration is updated
- [ ] kdump service starts successfully after reboot
- [ ] SysRq is enabled
- [ ] Crash dumps are generated correctly
- [ ] Backup files are created

## References and Documentation

- [Ubuntu Kernel Crash Dump Recipe](https://wiki.ubuntu.com/Kernel/CrashdumpRecipe)
- [RHEL kdump Documentation](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html/managing_monitoring_and_updating_the_kernel/installing-and-configuring-kdump_managing-monitoring-and-updating-the-kernel)
- [Fedora kdump Guide](https://docs.fedoraproject.org/en-US/fedora/latest/system-administrators-guide/kernel-module-driver-configuration/Working_with_Kernel_Crash_Dumps/)
- [Arch Linux kexec](https://wiki.archlinux.org/title/Kexec)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Author

Samuel Matildes

## Changelog

### v1.0.0 (2025-10-10)
- Initial release
- Multi-distribution support
- Automatic crashkernel configuration
- SysRq enablement
- Status checking functionality

## Support

For issues, questions, or contributions, please visit the [GitHub repository](https://github.com/yourusername/kdump-enabler).

