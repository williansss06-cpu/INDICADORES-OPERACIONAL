# Importação de Absenteísmo por operação e mês — 2026-09-24

Backup reversível criado antes da melhoria mensal.

A nova importação lê todas as abas de arquivos XLSX, identifica a coluna `Mês` quando existente e usa o nome da aba como fallback. Cada registro recebe `monthKey` no formato `YYYY-MM` e é separado por operação.

Validação da planilha recebida:

- Abas: Junho, Julho e Agosto;
- Registros válidos: 1.215;
- Julho: 823 registros;
- Agosto: 392 registros;
- Operações reconhecidas: MATRIZ e GLP_ACHE;
- Registros sem operação/mês: 0.

Nenhum dado do Supabase é alterado automaticamente pelo upload; a carga permanece local até o fluxo de persistência específico ser autorizado.
