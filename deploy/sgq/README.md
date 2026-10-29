# Gauzy na VPS da SGQ (ensaio da triagem de intimações)

Branch `ensaio/triagem-intimacoes` do fork `ffilipeguerra/ever-gauzy`. A branch `develop` fica igual
à do projeto original, para puxar as atualizações sem conflito.

## O que sobe

| Serviço | Imagem | Memória máx. | Porta no host |
|---|---|---|---|
| db | postgres:17-alpine | 1 GB | nenhuma |
| api | ghcr.io/ever-co/gauzy-api, fixada por digest | 2 GB | nenhuma |
| webapp | ghcr.io/ever-co/gauzy-webapp, fixada por digest | 256 MB | nenhuma, só pelo Traefik |

Um domínio só. O Traefik entrega o domínio à tela, e o nginx da tela repassa `/api/` para a API.
Ficam de fora Redis, worker, OpenSearch, MinIO, Cube e Zipkin, porque a triagem não precisa deles.

## Regras que valem aqui

- Nada sobe na VPS sem autorização expressa do Filipe.
- Antes de subir: cópia de segurança e smoke. Depois de subir: smoke de novo.
- Não mexe no namespace `atendimento` (Chatwoot) e nunca roda `docker stack deploy`.
- Segredos só no `.env` da VPS (chmod 600). Nunca no Git, nunca no chat.

## 1. Conferir o Traefik (só leitura)

```sh
docker ps --format '{{.Names}} {{.Image}}' | grep -i traefik
docker service ls 2>/dev/null | grep -i traefik
docker inspect $(docker ps -q -f name=traefik) --format '{{json .Args}}' 2>/dev/null
docker network ls
```

Do resultado sai o que vai no `.env`:

- `TRAEFIK_REDE`: a rede em que o Traefik está.
- `TRAEFIK_ENTRYPOINT`: o entrypoint HTTPS, em geral `websecure`.
- `TRAEFIK_CERTRESOLVER`: o nome do resolvedor de certificado.

**Conflito a resolver antes:** se o Traefik roda em modo swarm (`docker service ls` mostra o Traefik),
ele só lê etiquetas de *serviços* swarm. Contêineres de `docker compose` só aparecem para ele se o
provedor `docker` (não só o `swarm`) estiver ligado e a rede for `attachable`. Se não estiver, há
duas saídas, e as duas pedem decisão do Filipe:

1. ligar o provedor `docker` no Traefik, o que mexe na configuração dele;
2. usar um arquivo de rotas do provedor `file`, apontando para o IP interno da tela.

O DNS do domínio também precisa apontar para o IP da VPS antes de subir, senão o certificado não sai.

## 2. Subir (depois da autorização)

```sh
mkdir -p /opt/gauzy && cd /opt/gauzy        # copiar para cá os arquivos desta pasta
cp .env.vps.example .env && vi .env        # domínio e Traefik
./gerar-segredos.sh                        # senhas e segredos, sem imprimir
docker compose -p gauzy -f docker-compose.vps.yml --env-file .env pull
docker compose -p gauzy -f docker-compose.vps.yml --env-file .env up -d
docker compose -p gauzy logs -f api        # o primeiro boot cria o banco e semeia; leva alguns minutos
./smoke.sh
```

## 3. Desfazer

```sh
cd /opt/gauzy && docker compose -p gauzy -f docker-compose.vps.yml down   # para e remove os contêineres; o banco fica no volume
docker volume rm gauzy_gauzy_db                                           # só se for para apagar os dados também
```

Nada do que já existe na VPS é alterado: rede interna própria, volume próprio, nenhum arquivo de fora de `/opt/gauzy`.
O único ponto em comum é a rede do Traefik, onde a tela entra.

## 4. Cópia do banco

```sh
mkdir -p backup && docker compose -p gauzy exec -T db pg_dump -U gauzy gauzy | gzip > backup/gauzy-$(date +%F).sql.gz
```
