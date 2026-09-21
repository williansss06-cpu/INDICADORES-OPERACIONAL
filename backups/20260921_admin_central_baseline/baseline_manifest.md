# Baseline da Central Administrativa

O ponto de restauração da aplicação é o commit `6448069e868e66cfde9e9ba2ef9ed3df8c93f488`. O arquivo original `index.html` está preservado neste diretório e sua soma SHA-256 está registrada em `SHA256SUMS`.

A migration da Central foi aditiva. Ela não insere, remove ou atualiza linhas de indicadores, resultados, inventários, planos de ação ou absenteísmo. As únicas alterações de dados administrativas são a normalização dos perfis legados (`admin` para `super_admin` e `gestor` para `administrador_operacao`) e o preenchimento dos novos níveis de permissão a partir dos flags legados.

## Contagens de negócio verificadas após a aplicação

| Entidade | Registros verificados |
| --- | ---: |
| `sustentacao_indicadores` | 17 |
| `sustentacao_resultados` | 121 |
| `sustentacao_inventarios` | 4 |
| `sustentacao_plano_acao` | 9 |
| `absenteismo_registros` | 840 |

Os registros de Absenteísmo não foram recriados, excluídos ou migrados novamente. As colunas novas e os objetos de segurança foram validados no projeto `nemvssopcgmfxjndpmlw` antes do commit desta etapa.
