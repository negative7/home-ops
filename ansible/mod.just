set lazy
set positional-arguments
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

ansible_dir := justfile_dir() + '/ansible'

# Hosts are reached by IP: odesa only over WireGuard, lviv on VLAN20 (survives its network cutover)
lviv_host := '10.2.0.10'
odesa_host := '10.99.0.1'

[private]
[script]
default:
    just -l ansible

[doc('Install Ansible collections')]
deps:
    ansible-galaxy collection install -r "{{ ansible_dir }}/requirements.yaml"

[doc('Run the lviv playbook')]
[script]
lviv *args: _op
    just log info "Running playbook" "host" "lviv" "address" "{{ lviv_host }}"
    ansible-playbook -i "{{ lviv_host }}," "{{ ansible_dir }}/lviv/playbook.yaml" "$@"

[doc('Run the odesa playbook')]
[script]
odesa *args: _op
    just log info "Running playbook" "host" "odesa" "address" "{{ odesa_host }}"
    ansible-playbook -i "{{ odesa_host }}," "{{ ansible_dir }}/odesa/playbook.yaml" "$@"

# Both playbooks read secrets with `op read`
[private]
[script]
_op:
    op whoami >/dev/null 2>&1 || { just log error "1Password CLI is not signed in, run op signin first"; exit 1; }
