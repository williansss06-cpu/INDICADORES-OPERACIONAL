# Persistência da importação de Absenteísmo no Supabase — 2026-09-24

## Causa

O upload anterior apenas separava os dados em `localStorage`; não havia chamada de escrita para `absenteismo_registros`.

## Correção

O botão de confirmação agora grava via UPSERT usando a chave `operacao_id + mes_referencia + colaborador`. Registros existentes são atualizados sem alterar seus IDs; registros novos são inseridos. A RLS exige permissão de edição no módulo ABSENTEISMO.

A carga não remove históricos que estejam ausentes da planilha.
