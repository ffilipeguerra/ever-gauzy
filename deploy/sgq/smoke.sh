#!/bin/sh
# Smoke do Gauzy na VPS. Só lê. Sai com 0 quando tudo está VERDE.
set -u
cd "$(dirname "$0")"
DOM="$(grep '^GAUZY_DOMINIO=' .env | cut -d= -f2)"
falhas=0
ok()   { echo "VERDE    $1"; }
ruim() { echo "VERMELHO $1"; falhas=$((falhas + 1)); }

for s in db api webapp; do
	estado="$(docker compose -p gauzy -f docker-compose.vps.yml ps --format '{{.State}} {{.Health}}' "$s" 2>/dev/null)"
	case "$estado" in
		running\ healthy|running\ ) ok "contêiner $s: $estado" ;;
		*) ruim "contêiner $s: ${estado:-ausente}" ;;
	esac
done

# Nenhuma porta do Gauzy publicada no host
if docker compose -p gauzy -f docker-compose.vps.yml ps --format '{{.Publishers}}' | grep -q 'PublishedPort:[1-9]'; then
	ruim "há porta publicada no host"
else
	ok "nenhuma porta publicada no host"
fi

codigo="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "https://${DOM}/")"
[ "$codigo" = "200" ] && ok "tela https://${DOM}/ -> 200" || ruim "tela https://${DOM}/ -> $codigo"

codigo="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "https://${DOM}/api/health")"
[ "$codigo" = "200" ] && ok "API https://${DOM}/api/health -> 200" || ruim "API /api/health -> $codigo"

dias="$(echo | openssl s_client -servername "$DOM" -connect "$DOM:443" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)"
[ -n "$dias" ] && ok "certificado TLS válido até $dias" || ruim "sem certificado TLS"

docker stats --no-stream --format '{{.Name}} {{.MemUsage}}' | grep '^gauzy-' || true
[ "$falhas" -eq 0 ] && echo "smoke: VERDE" || echo "smoke: VERMELHO ($falhas)"
exit "$falhas"
