[English](README.md) | Português

# TurboClaude

Executa `claude -p` em horários agendados. Útil para resetar a janela de 5 horas do Claude em momentos estratégicos, permitindo mais uso durante o expediente.

Em vez das 2 janelas padrão num dia de trabalho, o TurboClaude envia um prompt leve em horários configuráveis (ex: 05:00, 10:00, 15:00) para destravar até 3 janelas ao longo do seu turno.

## Como funciona

1. Um script simples roda `claude -p "seu prompt"` nos horários agendados.
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

O instalador vai perguntar:

- O prompt a ser enviado (padrão: `Oi, bom dia`)
- Horários da agenda (padrão: `05:00,10:00,15:00`)
- Dias da semana (padrão: `Mon..Fri`)
- Se quer logar a resposta do Claude

Pronto. O timer já começa a rodar imediatamente.

## Configuração manual

Arquivo de config em `~/.config/turbo-claude/turbo-claude.conf`:

```bash
PROMPT="Oi, bom dia"
LOG_DIR="$HOME/.local/share/turbo-claude"
LOG_RESPONSE=true
# MODEL="claude-haiku-4-5-20251001"  # padrão, descomente pra sobrescrever
```

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
