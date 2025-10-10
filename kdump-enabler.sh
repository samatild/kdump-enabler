#!/usr/bin/env bash
#
# kdump-enabler: Automated kdump setup and configuration
#
# This script automatically enables and configures kdump across multiple
# Linux distributions. It handles package installation, service activation,
# and basic setup, ensuring systems are ready to collect kernel crash dumps.
#
# Author: Samuel Matildes
# License: MIT
# Repository: https://github.com/sam/kdump-enabler

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script variables
readonly SCRIPT_NAME="kdump-enabler"
readonly VERSION="1.0.0"
DISTRO=""
DISTRO_VERSION=""
PACKAGE_MANAGER=""
KDUMP_SERVICE=""
KDUMP_PACKAGES=()

#######################################
# Print colored messages
#######################################
print_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

#######################################
# Display script usage
#######################################
usage() {
    cat << EOF
${SCRIPT_NAME} v${VERSION}

Automatically enables and configures kdump for kernel crash dump collection.

USAGE:
    sudo $0 [OPTIONS]

OPTIONS:
    -h, --help          Show this help message
    -v, --version       Show version information
    -y, --yes           Skip confirmation prompts
    --no-sysrq          Skip sysrq crash enablement
    --check-only        Only check current configuration without making changes

EXAMPLES:
    sudo $0                 # Interactive mode
    sudo $0 -y              # Auto-confirm all prompts
    sudo $0 --check-only    # Check current kdump status

REQUIREMENTS:
    - Must be run as root or with sudo
    - Supported distributions: Ubuntu, Debian, RHEL, CentOS, Fedora, openSUSE, Arch Linux

EOF
    exit 0
}

#######################################
# Display version information
#######################################
show_version() {
    echo "${SCRIPT_NAME} v${VERSION}"
    exit 0
}

#######################################
# Check if running as root
#######################################
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root or with sudo"
        exit 1
    fi
}

#######################################
# Detect Linux distribution
#######################################
detect_distro() {
    print_info "Detecting Linux distribution..."
    
    if [[ -f /etc/os-release ]]; then
        # Read values safely without sourcing to avoid readonly variable conflicts
        DISTRO=$(grep -E "^ID=" /etc/os-release | cut -d'=' -f2 | tr -d '"')
        DISTRO_VERSION=$(grep -E "^VERSION_ID=" /etc/os-release | cut -d'=' -f2 | tr -d '"')
        DISTRO_VERSION="${DISTRO_VERSION:-unknown}"
        local DISTRO_NAME
        DISTRO_NAME=$(grep -E "^NAME=" /etc/os-release | cut -d'=' -f2 | tr -d '"')
        
        case "${DISTRO}" in
            ubuntu|debian|pop)
                PACKAGE_MANAGER="apt"
                KDUMP_SERVICE="kdump-tools"
                KDUMP_PACKAGES=("linux-crashdump" "kdump-tools" "kexec-tools")
                ;;
            rhel|centos|rocky|almalinux)
                PACKAGE_MANAGER="yum"
                KDUMP_SERVICE="kdump"
                KDUMP_PACKAGES=("kexec-tools")
                ;;
            fedora)
                PACKAGE_MANAGER="dnf"
                KDUMP_SERVICE="kdump"
                KDUMP_PACKAGES=("kexec-tools")
                ;;
            opensuse|opensuse-leap|opensuse-tumbleweed|sles)
                PACKAGE_MANAGER="zypper"
                KDUMP_SERVICE="kdump"
                KDUMP_PACKAGES=("kdump")
                ;;
            arch|manjaro)
                PACKAGE_MANAGER="pacman"
                KDUMP_SERVICE="kdump"
                KDUMP_PACKAGES=("kexec-tools")
                ;;
            *)
                print_error "Unsupported distribution: ${DISTRO}"
                exit 1
                ;;
        esac
        
        print_success "Detected: ${DISTRO_NAME} ${DISTRO_VERSION}"
        print_info "Package manager: ${PACKAGE_MANAGER}"
    else
        print_error "Cannot detect distribution (missing /etc/os-release)"
        exit 1
    fi
}

#######################################
# Check current kdump status
#######################################
check_kdump_status() {
    print_info "Checking current kdump configuration..."
    
    local kdump_active=false
    local sysrq_enabled=false
    
    # Check if kdump service exists and is active
    if systemctl list-unit-files "${KDUMP_SERVICE}.service" &>/dev/null || \
       systemctl status "${KDUMP_SERVICE}.service" &>/dev/null || \
       systemctl status "${KDUMP_SERVICE}" &>/dev/null; then
        if systemctl is-active --quiet "${KDUMP_SERVICE}.service" 2>/dev/null || \
           systemctl is-active --quiet "${KDUMP_SERVICE}" 2>/dev/null; then
            print_success "kdump service is active"
            kdump_active=true
        else
            print_warning "kdump service exists but is not active"
        fi
        
        if systemctl is-enabled --quiet "${KDUMP_SERVICE}.service" 2>/dev/null || \
           systemctl is-enabled --quiet "${KDUMP_SERVICE}" 2>/dev/null; then
            print_success "kdump service is enabled at boot"
        else
            print_warning "kdump service is not enabled at boot"
        fi
    else
        print_warning "kdump service not found"
    fi
    
    # Check crashkernel parameter in kernel command line
    if grep -q "crashkernel=" /proc/cmdline; then
        local crashkernel_value
        crashkernel_value=$(grep -oP 'crashkernel=\S+' /proc/cmdline)
        print_success "Crashkernel parameter set: ${crashkernel_value}"
    else
        print_warning "No crashkernel parameter found in kernel command line"
        print_info "A reboot will be required after configuration"
    fi
    
    # Check sysrq configuration
    if [[ -f /proc/sys/kernel/sysrq ]]; then
        local sysrq_value
        sysrq_value=$(cat /proc/sys/kernel/sysrq)
        if [[ ${sysrq_value} -ge 1 ]]; then
            print_success "SysRq is enabled (value: ${sysrq_value})"
            sysrq_enabled=true
        else
            print_warning "SysRq is disabled"
        fi
    fi
    
    # Check if crash dumps directory exists
    if [[ -d /var/crash ]]; then
        local crash_count
        crash_count=$(find /var/crash -type f -name "*.crash" 2>/dev/null | wc -l)
        print_info "Crash dump directory: /var/crash (${crash_count} dumps found)"
    fi
    
    echo ""
    if ${kdump_active} && ${sysrq_enabled}; then
        print_success "System is properly configured for kdump"
        return 0
    else
        print_warning "System requires kdump configuration"
        return 1
    fi
}

#######################################
# Install required packages
#######################################
install_packages() {
    print_info "Installing required packages..."
    
    case "${PACKAGE_MANAGER}" in
        apt)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq
            apt-get install -y "${KDUMP_PACKAGES[@]}"
            ;;
        yum)
            yum install -y -q "${KDUMP_PACKAGES[@]}"
            ;;
        dnf)
            dnf install -y -q "${KDUMP_PACKAGES[@]}"
            ;;
        zypper)
            zypper --non-interactive install "${KDUMP_PACKAGES[@]}"
            ;;
        pacman)
            pacman -Sy --noconfirm "${KDUMP_PACKAGES[@]}"
            ;;
        *)
            print_error "Unknown package manager: ${PACKAGE_MANAGER}"
            return 1
            ;;
    esac
    
    print_success "Packages installed successfully"
}

#######################################
# Configure crashkernel parameter
#######################################
configure_crashkernel() {
    print_info "Configuring crashkernel parameter..."
    
    # Determine appropriate crashkernel size based on RAM
    local total_ram_gb
    total_ram_gb=$(free -g | awk '/^Mem:/{print $2}')
    local crashkernel_size
    
    if [[ ${total_ram_gb} -lt 8 ]]; then
        crashkernel_size="256M"
    elif [[ ${total_ram_gb} -lt 16 ]]; then
        crashkernel_size="384M"
    else
        crashkernel_size="512M"
    fi
    
    print_info "Recommended crashkernel size: ${crashkernel_size} (Total RAM: ${total_ram_gb}GB)"
    
    # Check if crashkernel is already set
    if grep -q "crashkernel=" /proc/cmdline; then
        print_warning "Crashkernel parameter already set, skipping GRUB modification"
        return 0
    fi
    
    # Update GRUB configuration based on distro
    case "${DISTRO}" in
        ubuntu|debian|pop)
            if [[ -f /etc/default/grub ]]; then
                # Backup GRUB config
                cp /etc/default/grub /etc/default/grub.backup."$(date +%Y%m%d_%H%M%S)"
                
                # Add or update crashkernel parameter
                if grep -q "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub; then
                    sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"/GRUB_CMDLINE_LINUX_DEFAULT=\"crashkernel=${crashkernel_size} /" /etc/default/grub
                else
                    echo "GRUB_CMDLINE_LINUX_DEFAULT=\"crashkernel=${crashkernel_size}\"" >> /etc/default/grub
                fi
                
                # Update GRUB
                update-grub
                print_success "GRUB configuration updated"
            fi
            ;;
        rhel|centos|rocky|almalinux|fedora)
            if [[ -f /etc/default/grub ]]; then
                cp /etc/default/grub /etc/default/grub.backup."$(date +%Y%m%d_%H%M%S)"
                
                if grep -q "^GRUB_CMDLINE_LINUX=" /etc/default/grub; then
                    sed -i "s/GRUB_CMDLINE_LINUX=\"/GRUB_CMDLINE_LINUX=\"crashkernel=${crashkernel_size} /" /etc/default/grub
                else
                    echo "GRUB_CMDLINE_LINUX=\"crashkernel=${crashkernel_size}\"" >> /etc/default/grub
                fi
                
                # Update GRUB for BIOS and EFI systems
                if [[ -d /sys/firmware/efi ]]; then
                    grub2-mkconfig -o /boot/efi/EFI/$(echo "${DISTRO}" | tr '[:lower:]' '[:upper:]')/grub.cfg 2>/dev/null || \
                    grub2-mkconfig -o /boot/grub2/grub.cfg
                else
                    grub2-mkconfig -o /boot/grub2/grub.cfg
                fi
                print_success "GRUB2 configuration updated"
            fi
            ;;
        opensuse|opensuse-leap|opensuse-tumbleweed|sles)
            if [[ -f /etc/default/grub ]]; then
                cp /etc/default/grub /etc/default/grub.backup."$(date +%Y%m%d_%H%M%S)"
                
                if grep -q "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub; then
                    sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"/GRUB_CMDLINE_LINUX_DEFAULT=\"crashkernel=${crashkernel_size} /" /etc/default/grub
                else
                    echo "GRUB_CMDLINE_LINUX_DEFAULT=\"crashkernel=${crashkernel_size}\"" >> /etc/default/grub
                fi
                
                grub2-mkconfig -o /boot/grub2/grub.cfg
                print_success "GRUB2 configuration updated"
            fi
            ;;
        arch|manjaro)
            if [[ -f /etc/default/grub ]]; then
                cp /etc/default/grub /etc/default/grub.backup."$(date +%Y%m%d_%H%M%S)"
                
                if grep -q "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub; then
                    sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"/GRUB_CMDLINE_LINUX_DEFAULT=\"crashkernel=${crashkernel_size} /" /etc/default/grub
                else
                    echo "GRUB_CMDLINE_LINUX_DEFAULT=\"crashkernel=${crashkernel_size}\"" >> /etc/default/grub
                fi
                
                grub-mkconfig -o /boot/grub/grub.cfg
                print_success "GRUB configuration updated"
            fi
            ;;
    esac
}

#######################################
# Enable and start kdump service
#######################################
enable_kdump_service() {
    print_info "Enabling kdump service..."
    
    # Enable service at boot
    systemctl enable "${KDUMP_SERVICE}.service" 2>/dev/null || systemctl enable "${KDUMP_SERVICE}"
    print_success "kdump service enabled at boot"
    
    # Start service if crashkernel is already configured
    if grep -q "crashkernel=" /proc/cmdline; then
        systemctl start "${KDUMP_SERVICE}.service" 2>/dev/null || systemctl start "${KDUMP_SERVICE}" || {
            print_warning "Failed to start kdump service (may require reboot)"
        }
    else
        print_warning "kdump service will start after reboot (crashkernel parameter needs to be loaded)"
    fi
}

#######################################
# Enable SysRq crash trigger
#######################################
enable_sysrq() {
    print_info "Enabling SysRq crash trigger..."
    
    # Enable SysRq at runtime
    echo 1 > /proc/sys/kernel/sysrq
    print_success "SysRq enabled for current session"
    
    # Make SysRq persistent across reboots
    if [[ -f /etc/sysctl.conf ]]; then
        if grep -q "^kernel.sysrq" /etc/sysctl.conf; then
            sed -i 's/^kernel.sysrq.*/kernel.sysrq = 1/' /etc/sysctl.conf
        else
            echo "kernel.sysrq = 1" >> /etc/sysctl.conf
        fi
        print_success "SysRq configuration persisted to /etc/sysctl.conf"
    elif [[ -d /etc/sysctl.d ]]; then
        echo "kernel.sysrq = 1" > /etc/sysctl.d/99-kdump-sysrq.conf
        print_success "SysRq configuration persisted to /etc/sysctl.d/99-kdump-sysrq.conf"
    fi
    
    # Apply sysctl changes
    sysctl -p &>/dev/null || true
}

#######################################
# Configure kdump settings
#######################################
configure_kdump() {
    print_info "Configuring kdump settings..."
    
    # Create crash dump directory if it doesn't exist
    mkdir -p /var/crash
    chmod 755 /var/crash
    print_success "Crash dump directory: /var/crash"
    
    # Distribution-specific kdump configuration
    case "${DISTRO}" in
        ubuntu|debian|pop)
            if [[ -f /etc/default/kdump-tools ]]; then
                cp /etc/default/kdump-tools /etc/default/kdump-tools.backup."$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
                
                # Ensure kdump is enabled
                if grep -q "^USE_KDUMP=" /etc/default/kdump-tools; then
                    sed -i 's/^USE_KDUMP=.*/USE_KDUMP=1/' /etc/default/kdump-tools
                else
                    echo "USE_KDUMP=1" >> /etc/default/kdump-tools
                fi
                
                print_success "kdump-tools configured"
            fi
            ;;
        rhel|centos|rocky|almalinux|fedora|opensuse|opensuse-leap|opensuse-tumbleweed|sles)
            if [[ -f /etc/kdump.conf ]]; then
                cp /etc/kdump.conf /etc/kdump.conf.backup."$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
                
                # Ensure path is set
                if ! grep -q "^path /var/crash" /etc/kdump.conf; then
                    echo "path /var/crash" >> /etc/kdump.conf
                fi
                
                # Set core_collector if not set
                if ! grep -q "^core_collector" /etc/kdump.conf; then
                    echo "core_collector makedumpfile -l --message-level 1 -d 31" >> /etc/kdump.conf
                fi
                
                print_success "kdump.conf configured"
            fi
            ;;
    esac
}

#######################################
# Display post-installation instructions
#######################################
show_instructions() {
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗"
    echo -e "║                    KDUMP SETUP COMPLETED                       ║"
    echo -e "╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}IMPORTANT: A system reboot is required to apply all changes!${NC}"
    echo ""
    echo "After reboot, verify kdump is working:"
    echo "    sudo kdump-tools test      # Ubuntu/Debian"
    echo "    sudo kdumpctl showmem      # RHEL/CentOS/Fedora"
    echo "    sudo systemctl status ${KDUMP_SERVICE}"
    echo ""
    echo -e "To trigger a test crash dump (${RED}WILL REBOOT THE SYSTEM${NC}):"
    echo "    echo c | sudo tee /proc/sysrq-trigger"
    echo ""
    echo "Crash dumps will be saved to: /var/crash"
    echo ""
    echo -e "${GREEN}Documentation:${NC}"
    echo "    - Ubuntu/Debian: https://wiki.ubuntu.com/Kernel/CrashdumpRecipe"
    echo "    - RHEL/Fedora: https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html/managing_monitoring_and_updating_the_kernel/installing-and-configuring-kdump_managing-monitoring-and-updating-the-kernel"
    echo ""
}

#######################################
# Main function
#######################################
main() {
    local auto_yes=false
    local check_only=false
    local skip_sysrq=false
    
    # Parse command-line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                ;;
            -v|--version)
                show_version
                ;;
            -y|--yes)
                auto_yes=true
                shift
                ;;
            --check-only)
                check_only=true
                shift
                ;;
            --no-sysrq)
                skip_sysrq=true
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use -h or --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Print banner
    echo -e "${BLUE}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║                    KDUMP ENABLER v1.0.0                      ║
║                                                              ║
║         Automated kdump configuration for Linux              ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    # Check root privileges
    check_root
    
    # Detect distribution
    detect_distro
    echo ""
    
    # Check current status
    if check_kdump_status; then
        if ${check_only}; then
            exit 0
        fi
        
        if ! ${auto_yes}; then
            echo ""
            read -rp "kdump appears to be configured. Continue anyway? [y/N] " response
            if [[ ! ${response} =~ ^[Yy]$ ]]; then
                print_info "Exiting without changes"
                exit 0
            fi
        fi
    fi
    echo ""
    
    # Exit if check-only mode
    if ${check_only}; then
        exit 1
    fi
    
    # Confirm before proceeding
    if ! ${auto_yes}; then
        print_warning "This script will:"
        echo "  1. Install kdump packages (${KDUMP_PACKAGES[*]})"
        echo "  2. Configure crashkernel parameter in GRUB"
        echo "  3. Enable and start kdump service"
        if ! ${skip_sysrq}; then
            echo "  4. Enable SysRq crash trigger"
        fi
        echo "  5. Require a system reboot to complete setup"
        echo ""
        read -rp "Do you want to continue? [y/N] " response
        if [[ ! ${response} =~ ^[Yy]$ ]]; then
            print_info "Exiting without changes"
            exit 0
        fi
    fi
    echo ""
    
    # Execute configuration steps
    install_packages
    echo ""
    
    configure_crashkernel
    echo ""
    
    configure_kdump
    echo ""
    
    enable_kdump_service
    echo ""
    
    if ! ${skip_sysrq}; then
        enable_sysrq
        echo ""
    fi
    
    # Show completion message
    show_instructions
    
    print_success "kdump enabler completed successfully!"
    print_warning "Please reboot your system to apply all changes"
}

# Run main function
main "$@"

