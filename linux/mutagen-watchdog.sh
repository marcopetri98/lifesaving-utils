#!/usr/bin/env bash
# Pause any Mutagen sync session after MAX consecutive disconnected checks.
MAX=5
declare -A fails
while sleep 15; do
  while read -r id ok; do
    if [ "$ok" = true ]; then
      fails[$id]=0
    else
      fails[$id]=$(( ${fails[$id]:-0} + 1 ))
      [ "${fails[$id]}" -ge "$MAX" ] && mutagen sync pause "$id" && fails[$id]=0
    fi
  done < <(mutagen sync list --template '{{range .}}{{.Identifier}} {{if .Paused}}true{{else}}{{and .Alpha.Connected .Beta.Connected}}{{end}}{{"\n"}}{{end}}')
done
