# Sync Guide (Linux VM ↔ Mac)

## Clone on Mac
```bash
git clone git@github.com:parrsi01/securewave.git
cd securewave
```

## Daily workflow
```bash
git pull
# make changes
git add .
git commit -m "your message"
git push
```

## SSH key setup (Mac)
```bash
ssh-keygen -t ed25519 -C "parrsi01@luther.edu"
cat ~/.ssh/id_ed25519.pub
```
Add the public key at: https://github.com/settings/keys

## If using a different key
```bash
GIT_SSH_COMMAND='ssh -i ~/.ssh/your_key -o IdentitiesOnly=yes' git push
```
