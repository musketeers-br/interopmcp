#!/bin/bash
# Script: copy_interopmcp.sh
# Descrição: Copia interopmcp de /home/jose/dev/tmp/interopmcp para o repo atual
#          Sem histórico git, excluindo caches e arquivos desnecessários
#--------------------------------------------------------------------------------

SRC="/home/jose/dev/tmp/interopmcp"
DST="/home/jose/dev/interopmcp"

if [ ! -d "$SRC" ]; then
  echo "ERRO: Diretório de origem não encontrado: $SRC"
  exit 1
fi

echo "Iniciando cópia de $SRC para $DST..."
echo "----------------------------------------"

rsync -a --exclude=.git \
  --exclude='__pycache__' \
  --exclude='.venv' \
  --exclude='.pytest_cache' \
  --exclude='*.log' \
  --exclude='*.pyc' \
  "$SRC/" "$DST/"

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
  echo "----------------------------------------"
  echo "Cópia concluída com sucesso!"
  echo ""
  echo "Próximos passos no repo destino:"
  echo "1. cd $DST"
  echo "2. git status  (verificar arquivos atualizados)"
  echo "3. git log --oneline -3  (historico git original não foi copiado)"
else
  echo "----------------------------------------"
  echo "ERRO durante a cópia (código: $EXIT_CODE)"
  exit $EXIT_CODE
fi