#!/bin/bash
# r.sh '<read-only command>' — run one READ-ONLY command on the router and log it.
LOG=/home/mitchell/gemini/axe7800/repro/preflash-audit/evidence/router-commands.txt
printf '%s\t%s\n' "$(date -u +%FT%TZ)" "$1" >> "$LOG"
ssh -o BatchMode=yes -o IdentitiesOnly=yes -i ~/.ssh/axe7800_readonly -p 4324 admin@192.168.8.1 "$1" 2>&1 \
  | grep -v 'openssh.com/pq\|post-quantum\|store now, decrypt\|server may need'
