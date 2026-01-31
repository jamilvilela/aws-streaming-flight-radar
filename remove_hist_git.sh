# Remover do histórico com filter-branch
git filter-branch --force --index-filter \
"git rm --cached --ignore-unmatch \
infra\terraform.tfstate \
infra\terraform.tfstate.backup" \
--prune-empty --tag-name-filter cat -- --all

# Forçar push para reescrever o histórico remoto
git push origin --force --all
git push origin --force --tags

# Limpar repositório local:
rm -rf .git/refs/original/
git reflog expire --expire=now --all
git gc --prune=now --aggressive
