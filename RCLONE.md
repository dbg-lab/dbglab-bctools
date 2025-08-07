# SFTP to S3 Transfer with rclone

This guide explains how to set up efficient file transfers from SFTP servers to AWS S3 using rclone on an EC2 instance.

## Why rclone?

rclone is significantly better than custom scripts for this use case:
- **Native SFTP and S3 support** with optimized protocols
- **Built-in parallel transfers** (no need for GNU parallel)
- **Automatic retry** on failures and resume interrupted transfers
- **Progress reporting** and bandwidth limiting
- **Incremental sync** - only transfers new/changed files

## Prerequisites

- EC2 instance with rclone installed
- AWS credentials with S3 access permissions
- SFTP server credentials

## Step 1: Install rclone on EC2

If you're using the `setup_ec2_biotools.sh` script from this repository, rclone is automatically installed. Otherwise, install manually:

```bash
# SSH to your EC2 instance
ssh -i ~/.ssh/your-key.pem ec2-user@your-ec2-ip

# Install rclone
cd /tmp
curl -O https://downloads.rclone.org/rclone-current-linux-amd64.zip
unzip -q rclone-current-linux-amd64.zip
cd rclone-*-linux-amd64
sudo cp rclone /usr/local/bin/
```

## Step 2: Get AWS Credentials

You'll need your AWS Access Key ID and Secret Access Key for the account that has access to your S3 bucket. You can get these from:

1. AWS Console → IAM → Users → Your User → Security Credentials → Create Access Key
2. Make sure your user has S3 permissions for the target bucket

**Note**: You don't need to run `aws configure` - rclone will handle the credentials directly.

## Step 3: Configure rclone Remotes

### Configure SFTP Remote

```bash
rclone config create sftp-ucsf sftp \
    host fastq.ucsf.edu \
    user hiseq_user \
    pass your_sftp_password
```

### Configure S3 Remote

```bash
rclone config create s3-dbglab s3 \
    provider AWS \
    region us-east-2 \
    access_key_id YOUR_ACCESS_KEY \
    secret_access_key YOUR_SECRET_KEY
```

## Step 4: Test Configuration

```bash
# Test SFTP access
rclone ls sftp-ucsf:/SSD/illumina/ | head -5

# Test S3 access
rclone ls s3-dbglab:your-bucket/ | head -5
```

## Step 5: Transfer Files

### Basic Transfer
```bash
rclone sync sftp-ucsf:/path/to/source s3-dbglab:bucket/destination --progress
```

### Optimized Transfer
```bash
rclone sync sftp-ucsf:/path/to/source s3-dbglab:bucket/destination \
    --progress \
    --transfers 8 \
    --checkers 8 \
    --retries 3
```

### Example: Our Working Transfer
```bash
rclone sync sftp-ucsf:/SSD/illumina/20250801_LH00826_0072_B2333M5LT4/DG14275 \
    s3-dbglab:dbglab-tcsl/tcsl259 \
    --progress \
    --transfers 8
```

## Security Notes

- rclone encrypts passwords and access keys in its config file
- Limit S3 permissions to only the required buckets/paths
- Use IAM roles when possible instead of long-term access keys 