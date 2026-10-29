#!/bin/sh
# Preenche no .env, NA VPS, as senhas e os segredos que estiverem vazios.
# Não imprime nenhum valor: só diz quais chaves preencheu. Rodar de novo não troca
# o que já está preenchido (trocar DB_PASS depois do primeiro boot quebra o banco).
set -eu
cd "$(dirname "$0")"
[ -f .env ] || { echo "falta o .env: cp .env.vps.example .env"; exit 1; }
chmod 600 .env

preencher() {
	chave="$1"
	if grep -q "^${chave}=$" .env; then
		valor="$(openssl rand -hex 32)"
		sed -i "s|^${chave}=$|${chave}=${valor}|" .env
		echo "preenchido: ${chave}"
	fi
}

for k in DB_PASS JWT_SECRET JWT_REFRESH_TOKEN_SECRET JWT_VERIFICATION_TOKEN_SECRET \
	EXPRESS_SESSION_SECRET DEMO_SUPER_ADMIN_PASSWORD DEMO_ADMIN_PASSWORD DEMO_EMPLOYEE_PASSWORD; do
	preencher "$k"
done
echo "pronto. As senhas das contas ficam só no .env (chmod 600); o Filipe lê ali e troca no primeiro acesso."
