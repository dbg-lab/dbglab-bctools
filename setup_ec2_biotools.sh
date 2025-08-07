#!/bin/bash

# =============================================================================
# EC2 Bioinformatics Environment Setup Script
# =============================================================================
# This script sets up an Amazon Linux 2023 EC2 instance with all the tools
# needed for the dbglab-bctools bioinformatics workflow.
#
# Package Manager Strategy:
# - Uses dnf (not yum) as Amazon Linux 2023's native package manager
# - Tries to install tools via dnf first for better security and updates
# - Falls back to source compilation when packages aren't available
# - Maintains compatibility with original home directory installations
#
# Usage: 
#   scp -i ~/.ssh/key.pem setup_ec2_biotools.sh ec2-user@instance-ip:~/
#   ssh -i ~/.ssh/key.pem ec2-user@instance-ip "chmod +x setup_ec2_biotools.sh && ./setup_ec2_biotools.sh"
#
# Or run directly:
#   curl -sSL https://raw.githubusercontent.com/dbg-lab/dbglab-bctools/main/setup_ec2_biotools.sh | bash
# =============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running on Amazon Linux
check_os() {
    log_info "Checking operating system..."
    if ! grep -q "Amazon Linux" /etc/os-release; then
        log_error "This script is designed for Amazon Linux 2023"
        exit 1
    fi
    log_success "Running on Amazon Linux 2023"
}

# =============================================================================
# SECTION 1: System Updates and Basic Tools
# =============================================================================

install_system_basics() {
    log_info "Updating system packages..."
    sudo dnf update -y

    log_info "Installing development tools and essential packages..."
    sudo dnf groupinstall -y "Development Tools"
    
    log_info "Installing additional system dependencies..."
    sudo dnf install -y \
        htop \
        git \
        wget \
        unzip \
        gzip \
        parallel \
        sshpass \
        jq \
        zlib-devel \
        ncurses-devel \
        bzip2-devel \
        xz-devel \
        python3-pip \
        python3-devel
    
    log_info "Trying to install additional bioinformatics tools via package manager..."
    # Try to install common bioinformatics tools that might be available
    # These will fail silently if not available, and we'll compile from source later
    sudo dnf install -y \
        bedtools \
        bowtie2 \
        bcftools \
        htslib-tools \
        vcftools 2>/dev/null || log_info "Some bioinformatics packages not available via dnf"
    
    log_success "System basics installed"
}

# =============================================================================
# SECTION 2: Bioinformatics Tools Installation
# =============================================================================

install_flash2() {
    log_info "Installing FLASH2..."
    cd /tmp
    wget -q https://github.com/dstreett/FLASH2/archive/refs/tags/2.2.00.tar.gz
    tar -xzf 2.2.00.tar.gz
    cd FLASH2-2.2.00
    make
    
    # Install to system path
    sudo cp flash2 /usr/local/bin/
    
    # Also install to home directory (as per original script)
    mkdir -p ~/FLASH2-2.2.00
    cp flash2 ~/FLASH2-2.2.00/
    
    log_success "FLASH2 installed"
}

install_bwa() {
    log_info "Installing BWA..."
    
    # Try package manager first
    if sudo dnf install -y bwa 2>/dev/null; then
        log_success "BWA installed via package manager"
        
        # Also create home directory symlink for compatibility
        mkdir -p ~/bwa
        ln -sf /usr/bin/bwa ~/bwa/bwa 2>/dev/null || true
    else
        log_info "BWA not available via package manager, compiling from source..."
        cd /tmp
        git clone https://github.com/lh3/bwa.git
        cd bwa
        make
        sudo cp bwa /usr/local/bin/
        
        # Also install to home directory (as per original script)
        mkdir -p ~/bwa
        cp bwa ~/bwa/
        log_success "BWA compiled and installed from source"
    fi
}

install_samtools() {
    log_info "Installing samtools..."
    
    # Try package manager first
    if sudo dnf install -y samtools 2>/dev/null; then
        log_success "samtools installed via package manager"
        
        # Also create home directory symlink for compatibility
        mkdir -p ~/samtools
        ln -sf /usr/bin/samtools ~/samtools/samtools 2>/dev/null || true
    else
        log_info "samtools not available via package manager, compiling from source..."
        cd /tmp
        wget -q https://github.com/samtools/samtools/releases/download/1.19.2/samtools-1.19.2.tar.bz2
        tar -xjf samtools-1.19.2.tar.bz2
        cd samtools-1.19.2
        ./configure --prefix=/usr/local
        make
        sudo make install
        
        # Also install to home directory (as per original script)
        mkdir -p ~/samtools
        cp samtools ~/samtools/
        log_success "samtools compiled and installed from source"
    fi
}

install_ugrep() {
    log_info "Installing ugrep..."
    
    # Try package manager first
    if sudo dnf install -y ugrep 2>/dev/null; then
        log_success "ugrep installed via package manager"
    else
        log_info "ugrep not available via package manager, compiling from source..."
        cd /tmp
        wget -q https://github.com/Genivia/ugrep/archive/refs/tags/v7.5.0.tar.gz
        tar -xzf v7.5.0.tar.gz
        cd ugrep-7.5.0
        ./configure --prefix=/usr/local
        make
        sudo make install
        log_success "ugrep compiled and installed from source"
    fi
}

install_fastq_multx() {
    log_info "Installing fastq-multx..."
    
    # Try package manager first
    if sudo dnf install -y fastq-multx 2>/dev/null; then
        log_success "fastq-multx installed via package manager"
        
        # Also create home directory symlink for compatibility
        mkdir -p ~/fastq-multx-1.4.3
        ln -sf /usr/bin/fastq-multx ~/fastq-multx-1.4.3/fastq-multx 2>/dev/null || true
    else
        log_info "fastq-multx not available via package manager, compiling from source..."
        cd /tmp
        wget -q https://github.com/brwnj/fastq-multx/archive/refs/tags/1.4.3.tar.gz
        tar -xzf 1.4.3.tar.gz
        cd fastq-multx-1.4.3
        make
        sudo cp fastq-multx /usr/local/bin/
        
        # Also install to home directory (as per original script)
        mkdir -p ~/fastq-multx-1.4.3
        cp fastq-multx ~/fastq-multx-1.4.3/
        log_success "fastq-multx compiled and installed from source"
    fi
}

install_rclone() {
    log_info "Installing rclone..."
    cd /tmp
    curl -O https://downloads.rclone.org/rclone-current-linux-amd64.zip
    unzip -q rclone-current-linux-amd64.zip
    cd rclone-*-linux-amd64
    
    # Install to system path
    sudo cp rclone /usr/local/bin/
    sudo chown root:root /usr/local/bin/rclone
    sudo chmod 755 /usr/local/bin/rclone
    
    # Install manpage
    sudo mkdir -p /usr/local/share/man/man1
    sudo cp rclone.1 /usr/local/share/man/man1/
    sudo mandb
    
    log_success "rclone installed"
}

# =============================================================================
# SECTION 3: Python Environment Setup
# =============================================================================

setup_python_environment() {
    log_info "Setting up Python environment..."
    
    # Upgrade pip
    python3 -m pip install --user --upgrade pip
    
    # Install common bioinformatics Python packages
    python3 -m pip install --user \
        numpy \
        pandas \
        scipy \
        matplotlib \
        seaborn \
        biopython \
        pysam \
        argparse \
        regex \
        "pyarrow>=10.0.1" 
    
    log_success "Python environment configured"
}

# =============================================================================
# SECTION 4: Basic Directory Setup
# =============================================================================

setup_basic_directories() {
    log_info "Setting up basic working directories..."
    
    # Create basic working directory
    mkdir -p ~/data
    
    log_info "Note: Project-specific directories should be created as needed"
    log_info "Note: /large_tmp should be set up as a separate EBS volume"
    
    log_success "Basic directories created"
}

# =============================================================================
# SECTION 5: Repository and Scripts Setup
# =============================================================================

setup_repository() {
    log_info "Setting up dbglab-bctools repository access..."
    
    # If running from curl (not in repo), clone it
    if [ ! -f "old/sftp_to_s3.sh" ]; then
        log_info "Cloning repository since we're not running from within it..."
        cd ~
        if [ -d "dbglab-bctools" ]; then
            log_warning "Repository already exists, updating..."
            cd dbglab-bctools
            git pull
        else
            git clone https://github.com/dbg-lab/dbglab-bctools.git
            cd dbglab-bctools
        fi
        
        # Make the script executable
        chmod +x old/sftp_to_s3.sh
        log_success "Repository cloned and configured"
    else
        log_info "Already running from within repository"
        chmod +x old/sftp_to_s3.sh
        log_success "Repository scripts made executable"
    fi
}

# =============================================================================
# SECTION 6: AWS Configuration
# =============================================================================

configure_aws() {
    log_info "AWS CLI is already installed. Version:"
    aws --version
    
    log_warning "AWS credentials need to be configured manually:"
    log_warning "  Run: aws configure"
    log_warning "  Or set up IAM roles for EC2 instance"
}

# =============================================================================
# SECTION 7: Verification and Testing
# =============================================================================

verify_installation() {
    log_info "Verifying installation..."
    
    # Check system tools
    local tools=("git" "parallel" "sshpass" "jq" "python3")
    for tool in "${tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            log_success "$tool: $(command -v $tool)"
        else
            log_error "$tool: NOT FOUND"
        fi
    done
    
    # Check bioinformatics tools
    local bio_tools=("flash2" "bwa" "samtools" "ugrep" "fastq-multx" "rclone")
    for tool in "${bio_tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            log_success "$tool: $(command -v $tool)"
        else
            log_error "$tool: NOT FOUND"
        fi
    done
    
    # Check additional bioinformatics tools that might be available
    local optional_tools=("bedtools" "bowtie2" "bcftools" "vcftools")
    for tool in "${optional_tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            log_success "$tool: $(command -v $tool) (bonus tool)"
        fi
    done
    
    # Check home directory installations
    log_info "Checking home directory installations..."
    for dir in "FLASH2-2.2.00" "bwa" "samtools" "fastq-multx-1.4.3"; do
        if [ -d ~/"$dir" ]; then
            log_success "~/$dir: EXISTS"
        else
            log_warning "~/$dir: NOT FOUND"
        fi
    done
    
    # Check Python packages
    log_info "Checking Python packages..."
    python3 -c "import numpy, pandas, biopython" 2>/dev/null && \
        log_success "Python packages: OK" || \
        log_warning "Some Python packages may be missing"
}

create_usage_info() {
    log_info "Creating usage information file..."
    cat > ~/USAGE.md << 'EOF'
# EC2 Bioinformatics Environment

This instance has been configured with all tools needed for the dbglab-bctools workflow.

## Installed Tools

### System Tools
- git, parallel, sshpass, jq
- Development tools (gcc, make, etc.)

### Bioinformatics Tools
- FLASH2 v2.2.00 (compiled from source)
- BWA (from package manager or compiled from source)
- samtools (from package manager or v1.19.2 compiled from source)
- ugrep (from package manager or v7.5.0 compiled from source)
- fastq-multx (from package manager or v1.4.3 compiled from source)
- rclone (latest binary)
- Additional tools if available: bedtools, bowtie2, bcftools, vcftools

### Python Environment
- Python 3.9.23 with numpy, pandas, biopython, etc.

## Repository
- dbglab-bctools cloned to ~/dbglab-bctools
- Main script: ~/dbglab-bctools/old/sftp_to_s3.sh

## Usage

1. Configure AWS credentials:
   ```bash
   aws configure
   ```

2. Source the script to load functions:
   ```bash
   source ~/dbglab-bctools/old/sftp_to_s3.sh
   ```

3. Configure rclone for SFTP and S3 (recommended for file transfers):
   ```bash
   # Configure SFTP remote
   rclone config create sftp-ucsf sftp host fastq.ucsf.edu user hiseq_user pass YOUR_PASSWORD
   
   # Configure S3 remote (or use AWS credentials)
   rclone config create s3-dbglab s3 provider AWS region us-east-1
   
   # Transfer files
   rclone sync sftp-ucsf:/path/to/source s3-dbglab:bucket/prefix --progress
   ```

4. Alternative: Test the download_fastq_sample function:
   ```bash
   # Edit the script to set SFTP credentials, then:
   download_fastq_sample "your_file.fastq.gz" 1000 "./samples"
   ```

## Directory Structure
- ~/data - Basic working directory
- Project-specific directories created as needed
- /large_tmp - Set up as separate EBS volume (not created by this script)

## Next Steps
1. Configure SFTP credentials in the script
2. Set up AWS credentials or IAM roles
3. Test with your FASTQ files
EOF

    log_success "Usage information created at ~/USAGE.md"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    log_info "Starting EC2 bioinformatics environment setup..."
    log_info "This may take 10-15 minutes to complete."
    
    check_os
    install_system_basics
    install_flash2
    install_bwa
    install_samtools
    install_ugrep
    install_fastq_multx
    install_rclone
    setup_python_environment
    setup_basic_directories
    setup_repository
    configure_aws
    verify_installation
    create_usage_info
    
    log_success "Setup completed successfully!"
    log_info "Instance is ready for bioinformatics workflows."
    log_info "See ~/USAGE.md for next steps."
    log_warning "Don't forget to configure AWS credentials!"
}

# Run main function
main "$@" 