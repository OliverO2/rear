# Prevent SSH security vulnerabilities:
# - https://github.com/rear/rear/issues/1511 - Security Vulnerability (Privilege Escalation): SSH private user key disclosure for root account
# - https://github.com/rear/rear/issues/1512 - Security Vulnerability (Gain Information): SSH private host key disclosure
# Generate host key for incoming SSH which was excluded from backup by prep/INTERNAL/default/205_secure_ssh_private_keys.sh
Log "Generating SSH host key"
ssh-keygen -t ed25519 -N '' -f "$ROOTFS_DIR/etc/ssh/ssh_host_ed25519_key"
