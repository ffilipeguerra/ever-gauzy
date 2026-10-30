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

## 1. Como o Traefik enxerga o Gauzy (conferido na VPS em 30/10/2026)

O Traefik é o do Easypanel (`easypanel-traefik`, Traefik 3.6.7), em swarm. Ele não lê etiquetas de
contêiner de compose, então o Gauzy segue o mesmo caminho que o sgq-bridge já usa:

- a tela entra na rede `easypanel` (overlay, attachable) com o apelido `gauzy-webapp`;
- o arquivo `traefik-gauzy.yaml` vai para `/etc/easypanel/traefik/config/gauzy.yaml` e aponta o
  domínio para `http://gauzy-webapp:4200/`;
- entrypoints `http` e `https`, middleware `redirect-to-https` (definido no main.yaml do Easypanel)
  e certresolver `letsencrypt`, iguais aos do sgq-bridge.

O Easypanel só reescreve `main.yaml`; o arquivo próprio sobrevive às regerações dele.
Não se mexe no `main.yaml` nem no serviço do Traefik.

O DNS do domínio (registro A para 179.198.99.14, na i7host) precisa existir antes de copiar o arquivo
de rota, senão o Let's Encrypt falha a validação.

## 2. Subir (depois da autorização)

```sh
mkdir -p /opt/gauzy && cd /opt/gauzy        # copiar para cá os arquivos desta pasta
cp .env.vps.example .env && vi .env        # domínio
./gerar-segredos.sh                        # senhas e segredos, sem imprimir
docker compose -p gauzy -f docker-compose.vps.yml --env-file .env pull
docker compose -p gauzy -f docker-compose.vps.yml --env-file .env up -d
docker compose -p gauzy logs -f api        # o primeiro boot cria o banco e semeia; leva alguns minutos
# com a API saudável e o DNS apontado:
sed "s/DOMINIO/$(grep '^GAUZY_DOMINIO=' .env | cut -d= -f2)/" traefik-gauzy.yaml > /etc/easypanel/traefik/config/gauzy.yaml
./smoke.sh
```

## 3. Desfazer

```sh
rm /etc/easypanel/traefik/config/gauzy.yaml                               # tira a rota; o Traefik relê sozinho
cd /opt/gauzy && docker compose -p gauzy -f docker-compose.vps.yml down   # para e remove os contêineres; o banco fica no volume
docker volume rm gauzy_gauzy_db                                           # só se for para apagar os dados também
```

Fora de `/opt/gauzy`, o Gauzy só deixa o arquivo `gauzy.yaml` na pasta de rotas do Traefik.
O único ponto em comum com o resto da VPS é a rede `easypanel`, onde só a tela entra.

## 4. Cópia do banco

```sh
mkdir -p backup && docker compose -p gauzy exec -T db pg_dump -U gauzy gauzy | gzip > backup/gauzy-$(date +%F).sql.gz
```
