# Prevent SSH security vulnerabilities:
# - https://github.com/rear/rear/issues/1511 - Security Vulnerability (Privilege Escalation): SSH private user key disclosure for root account
# - https://github.com/rear/rear/issues/1512 - Security Vulnerability (Gain Information): SSH private host key disclosure
COPY_AS_IS_EXCLUDE=( "${COPY_AS_IS_EXCLUDE[@]}" /etc/ssh/ssh_host_* /root/.ssh/id_* )
