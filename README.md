# Chrome Refresher

Scripts and Ansible playbooks to launch multiple Google Chrome instances across worker machines and automatically
refresh a target page at precisely scheduled times.

## Requirements for the Ansible control machine

- ansible installed
- passlib installed: `python3 -m pip install --user passlib`
- RDP client installed (Microsoft Remote Desktop)

## Configuration

Adjust the `execution.yml` Ansible playbook or write your own launcher instead of the 'launch_2by2.sh' script.

The main script with usage instructions is in `chrome_reload_at_ms.sh`.

### Secrets

Create an Ansible vault file for the necessary secrets: `ansible-vault create secrets.yml`

Add the following secrets to the vault file:

```bash
rdp_user_password: "VerySecretPasswordHere"
```

### Hosts

Generate a new SSH key pair for the worker authentication:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/my_key
```

Create the worker VMs on a hyperscaler of your choice, e.g. [Hetzner Cloud](https://www.hetzner.com/).

Configure your available worker WMs in `hosts.ini` under `[chrome_workers]`:

```
[chrome_workers]
vm-worker-1 target_ms_post="0,010,050,200" ansible_host=1.2.3.4 ansible_user=root ansible_ssh_private_key_file=~/.ssh/hetzner_key
vm-worker-2 target_ms_post="10,020,075,250" ansible_host=5.6.7.8 ansible_user=root ansible_ssh_private_key_file=~/.ssh/hetzner_key
vm-worker-3 target_ms_post="20,030,100,300" ansible_host=9.10.11.12 ansible_user=root ansible_ssh_private_key_file=~/.ssh/hetzner_key
```

The `target_ms_post` variable defines the times at which the Chrome instance should be refreshed (in milliseconds
relative to `target_date`).

## Deployment

Test the host connectivity:

```bash
ansible -i hosts.ini chrome_workers -m ping
```

Run the deployment playbook:

```bash
ansible-playbook -i hosts.ini deployment.yml --ask-vault-pass
```

## Execution

> ⚠️ Before running the execution playbook, connect to all workers via RDP (otherwise chrome will run in headless mode).

Run the execution playbook:

```bash
ansible-playbook -i hosts.ini execution.yml --ask-vault-pass
```
