[English](README.md) | Português

# TurboClaude

Executa `claude -p` em horários agendados. Útil para resetar a janela de 5 horas do Claude em momentos estratégicos, permitindo mais uso durante o expediente.

Em vez das 2 janelas padrão num dia de trabalho, o TurboClaude envia um prompt leve em horários configuráveis (ex: 05:00, 10:00, 15:00) para destravar até 3 janelas ao longo do seu turno.

## Como funciona

1. Um script simples roda `claude -p "seu prompt" --model claude-haiku-4-5-20251001` nos horários agendados.
2. Cada execução fica registrada com timestamp em `~/.local/share/turbo-claude/`.
3. Um timer do systemd (com fallback pra cron) dispara o script.
4. Configure o prompt, horários e dias em `~/.config/turbo-claude/turbo-claude.conf`.

## Requisitos

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code/overview) instalado e autenticado
- Linux com systemd (ou cron como fallback)

## Instalação

```bash
git clone https://github.com/BrennoKM/TurboClaude.git
cd TurboClaude
chmod +x install.sh
./install.sh
```

O instalador detecta o idioma pelo `$LANG` do sistema. Pra forçar um idioma: `./install.sh --lang pt` ou `./install.sh --lang en`.

O instalador vai perguntar:

- O prompt a ser enviado (padrão: `Oi`)
- Se quer modo avançado (veja abaixo) ou modo guiado
- No modo guiado: horários (padrão: `04:55,10:00,15:05`) e dias da semana (padrão: `*`, ou seja, todo dia)
- Se quer logar a resposta do Claude
- Se quer testar agora mesmo, ao final

Pronto. O timer já começa a rodar imediatamente.

### Qual agendador é usado

Se o sistema tem systemd e cron disponíveis, o instalador pergunta qual usar (padrão: systemd). Se só um dos dois existir, usa o que tiver, avisando quando cai no cron. Se nenhum existir, para com erro antes de perguntar qualquer outra coisa. O `test.sh` (veja abaixo) sempre mostra qual agendador está ativo.

### Modo avançado

Se você quer controlar o agendamento diretamente em vez de responder horários/dias, o modo avançado deixa você informar:

- A expressão `OnCalendar` do systemd direto (ex: `*-*-* 05,10,15:00:00`), múltiplas expressões separadas por `;`
- A expressão cron equivalente (5 campos), usada caso o sistema não tenha systemd

## Configuração manual

Arquivo de config em `~/.config/turbo-claude/turbo-claude.conf`:

```bash
PROMPT="Oi"
LOG_DIR="$HOME/.local/share/turbo-claude"
LOG_RESPONSE=true
# MODEL="claude-haiku-4-5-20251001"  # padrão, descomente pra sobrescrever
```

## Testando

```bash
./test.sh
```

Dispara uma execução agora (via systemd/cron se instalado, direto senão), mostra as novas linhas de log e retorna código de saída 0/1 conforme sucesso ou falha. Pode ser usado tanto pra validar manualmente quanto em automação (ex: CI, outro cron de verificação). Mostra também qual agendador está ativo (systemd timer ou crontab).

Esse modo padrão dispara o service manualmente, então prova que o *comando* funciona no ambiente do agendador, mas não prova que o agendamento em si vai disparar sozinho no horário certo.

Pra provar isso de verdade, sem disparar nada manualmente:

```bash
./test.sh --wait 60
```

Isso adiciona um disparo extra temporário pra daqui a 60 segundos, **sem mexer no agendamento original** (o timer/crontab de produção continua intacto durante o teste, então se um horário real cair dentro da janela do teste ele dispara normalmente também). Espera o disparo extra acontecer **sozinho**, e remove ele em seguida, restaurando o agendamento original exatamente como estava (mesmo se você cancelar com Ctrl+C). No caso do cron, a granularidade mínima é de 1 minuto (limitação do próprio cron), então o tempo de espera é arredondado pra cima.

## Rodando em Docker (várias contas/pessoas)

Se você quer rodar o TurboClaude num servidor pra você e pra outras pessoas (cada uma com sua própria conta Claude), não use o `install.sh` direto (ele avisa isso na hora). Use:

```bash
./docker-new-account.sh <nome>
```

Ele pergunta prompt/horários/dias/log (igual o `install.sh` guiado, incluindo o modo avançado com expressão cron manual) e adiciona um serviço novo no `docker-compose.yml` automaticamente, com suas próprias pastas em `accounts/<nome>/` (credenciais e logs isolados de qualquer outra conta).

Também pergunta o **timezone** (padrão: detectado do próprio host). Sem isso o container roda em UTC e o cron dispara nos horários errados. Aceita nome IANA (`America/Sao_Paulo`) ou deslocamento (`UTC-3`, `-3`, `GMT+2`), a conversão de sinal é feita automaticamente.

```bash
docker compose up -d turbo-claude-<nome>
docker exec -it turbo-claude-<nome> claude auth login
```

O `claude auth login` gera uma URL de autenticação (a pessoa abre no navegador dela e cola o código de volta). Sem isso, o container roda mas toda execução falha com "Not logged in".

Cada container já sobe com `restart: unless-stopped`, então sobrevive a reboot da máquina sem precisar de mais nada.

### Vendo logs de uma conta no Docker

As execuções aparecem em dois lugares:

```bash
docker logs -f turbo-claude-<nome>
```

E também no arquivo por dia, que como esse diretório já é montado como volume, você lê direto do host, sem precisar de `docker exec`:

```bash
cat accounts/<nome>/logs/$(date +%F).log
tail -f accounts/<nome>/logs/$(date +%F).log
```

Pra testar uma conta específica (inclusive com `--wait`, veja acima):

```bash
./test.sh --container turbo-claude-<nome> --wait 60
```

### Removendo uma conta

```bash
./docker-remove-account.sh <nome>
```

Para o container, remove a imagem e o serviço do `docker-compose.yml`, e pergunta se você também quer apagar as credenciais e logs em `accounts/<nome>/` (padrão: manter).

## Visualizando logs

```bash
journalctl --user -u turbo-claude.service -n 20
```

Ou leia o log diário diretamente:

```bash
cat ~/.local/share/turbo-claude/$(date +%F).log
```

## Alterando a agenda

```bash
systemctl --user edit turbo-claude.timer
```

Depois `systemctl --user daemon-reload` e reinicie o timer.

Ou edite o arquivo direto em `~/.config/systemd/user/turbo-claude.timer`.

Para ver as próximas execuções:

```bash
systemctl --user list-timers turbo-claude.timer
```

## Desinstalando

```bash
./uninstall.sh
```

Remove o timer/service do systemd (ou a entrada do crontab) e o script instalado. Pergunta se você também quer apagar config e logs.
