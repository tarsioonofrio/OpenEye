# Síntese do OpenEye_FPGA para diferentes malhas de PEs

## Escopo e proveniência

Esta comparação sintetiza o topo completo `OpenEye_FPGA` com um cluster e malhas
quadradas de 2×2, 3×3, 4×4 e 6×6 PEs. Todas as configurações foram sintetizadas
no checkout da Paxos `/sim/tarsio/OpenEye`, a partir do commit
`0c3da68b41f246f36839917014c1a85e8e566350`, usando Cadence Genus 23.14-s090_1,
biblioteca TSMC28 TT, 0,90 V, 25 °C e clock de 2 ns.

O topo usa `SERIAL=1`, portanto há um multiplicador por PE: 4, 9, 16 e 36,
respectivamente. `NUM_GLB_IACT=2` foi mantido constante; `NUM_GLB_PSUM` e
`NUM_GLB_WGHT` acompanham a dimensão da malha. Os relatórios são do wrapper
`OpenEye_FPGA`, que inclui DMA, buffers e controle junto ao núcleo de cálculo.

## Resultados

| PEs | Multiplicadores | Células mapeadas | Área de células | Área total do relatório | Slack mínimo (30 caminhos) | Potência vectorless |
|---:|---:|---:|---:|---:|---:|---:|
| 2×2 | 4 | 21.976 | 27.471,024 | 37.392,557 | 382 ps | 16,4518 mW |
| 3×3 | 9 | 37.350 | 45.693,270 | 62.521,416 | 228 ps | 28,5111 mW |
| 4×4 | 16 | 57.558 | 69.518,610 | 95.414,557 | 209 ps | 42,1051 mW |
| 6×6 | 36 | 115.556 | 135.975,672 | 187.989,482 | 166 ps | 81,0774 mW |

As áreas estão nas unidades apresentadas pelo Genus para a biblioteca usada.
“Área total” é a coluna `Total-Area` do relatório hierárquico; “área de células”
é `Cell-Area`. As células de memória abstratas têm área zero nos relatórios de
contagem lógica (`logic_abstract`: 33, 64, 106 e 227, respectivamente), portanto
estes números não caracterizam o tamanho físico das memórias.

## Limites da interpretação

`power_vectorless.rpt` é uma estimativa do Genus sem atividade do workload. Os
valores não são potência medida para a convolução C=2/F=6. Esse workload não é
fixado nesta síntese; uma comparação de potência baseada em atividade requer
uma simulação funcional validada da mesma revisão/configuração e a geração de
atividade correspondente. A abstração das RAMs também exclui sua potência e
área de armazenamento.

O fluxo não inclui placement nem routing. O slack é pré-layout, estimado pelo
Genus, sob as constraints indicadas; não equivale a fechamento temporal físico.
As execuções validam elaboração, síntese e mapeamento lógico, não a
funcionalidade da convolução.

## Artefatos

Os netlists e relatórios completos permanecem no único checkout da Paxos, em:

- `asic/openeye_fpga/results/pe2x2_clusters-1x1-final-0c3da68/`
- `asic/openeye_fpga/results/pe3x3_clusters-1x1/`
- `asic/openeye_fpga/results/pe4x4_clusters-1x1/`
- `asic/openeye_fpga/results/pe6x6_clusters-1x1/`

Cada diretório contém os parâmetros gerados, `netlist/OpenEye_FPGA_mapped.v`,
`reports/area.rpt`, `reports/gates.rpt`, `reports/timing.rpt` e
`reports/power_vectorless.rpt`. Os resultados são artefatos locais ignorados
pelo Git; este documento registra as métricas e a proveniência, mas não inclui
os netlists ou logs volumosos no repositório.
