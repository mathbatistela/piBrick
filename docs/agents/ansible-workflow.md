# Ansible workflow

## Running it

From a control machine (e.g. this Mac), over SSH, against the `pibrick` inventory group:

```sh
cd ansible
ansible-playbook -i inventory.ini site.yml --limit piBrick --check --diff   # dry run first
ansible-playbook -i inventory.ini site.yml --limit piBrick                  # apply for real
```

Locally, from a session on the Pi itself (repo cloned there per `access.md`), against the `local`
group (`ansible_connection=local`):

```sh
cd ~/piBrick/ansible
ansible-playbook -i inventory.ini site.yml --limit local --check --diff
ansible-playbook -i inventory.ini site.yml --limit local
```

Always dry-run (`--check --diff`) before applying for real, and read the diff — see
`scope-and-safety.md` for when to confirm with the user before the real (non-check) run.

## Dotfiles are one-directional: repo → device

`dotfiles/` in this repo is the source of truth. The `dotfiles` Ansible role copies *from* here *to*
the device; nothing copies the other direction automatically. If something gets changed live on the
device (by hand, or by DMS regenerating its own config fragments) and it's worth keeping, pull it back
into the repo explicitly — the playbook will otherwise overwrite it back to what's in `dotfiles/` on the
next run.

## Adding a new dotfile

1. Pull the live file from the device:
   ```sh
   scp mbatistela@192.168.1.99:<path-on-device> dotfiles/<category>/<name>
   ```
2. Add a `ansible.builtin.copy` task for it in the relevant role under `ansible/roles/` (see
   `ansible/roles/dotfiles/tasks/main.yml` for the pattern — `src` is relative to `playbook_dir`, `dest`
   is the absolute path on the target). Add a `become: true` if the destination is outside the user's
   home directory (e.g. `/etc/...`), like the `wayvnc` config task does.
3. Dry-run (`--check --diff`) to confirm the diff is empty (i.e. the file you copied out matches what
   gets copied back in) before committing.

## Adding a new apt package

Add it to the `name` list in `ansible/roles/packages/tasks/main.yml`. Don't add kernel-driver build
dependencies there — those belong to `pibrick-driver`'s own `install.sh` (see `scope-and-safety.md`).
