# Síntese FPGA: workload oficial C=2/F=6, MACs=1

## Configurações sintetizadas

As duas configurações abaixo correspondem aos casos funcionais aprovados no
topo `OpenEye_FPGA` para a convolução oficial C=2/F=6. Cada PE foi sintetizado
com `PARALLEL_MACS=1` e `SERIAL=1`; a grade possui dois clusters organizados
como 1 linha × 2 colunas. O formato PE é colunas × linhas por cluster.

| Configuração | PEs por cluster | Clusters | PEs/MACs totais |
| --- | ---: | ---: | ---: |
| 4×3 | 12 | 2 | 24 |
| 4×4 | 16 | 2 | 32 |

Parâmetros comuns: `NUM_GLB_IACT=3`, `NUM_GLB_PSUM=4` (colunas),
`CLUSTER_ROWS=1`, `CLUSTER_COLUMNS=2`, `PARALLEL_MACS=1`, `SERIAL=1`,
`SPARSITY_EN=1`. `NUM_GLB_WGHT` é 3 para 4×3 e 4 para 4×4.

## Resultados Genus

| Métrica | 4×3 | 4×4 |
| --- | ---: | ---: |
| Resultado | `Normal exit`, exit 0 | `Normal exit`, exit 0 |
| Tempo de parede reportado pelo Genus | 30 min 36 s | 35 min 28 s |
| Células standard mapeadas | 66.505 | 81.515 |
| Área de células standard (µm²) | 79.122,960 | 95.876,802 |
| Slack setup no pior caminho reportado | +394 ps | +394 ps |
| Potência vectorless total (mW) | 49,1846 | 58,9395 |

Os dois relatórios de timing marcam o pior caminho como `MET`, com período de
clock de 2 ns. O caminho limitante está na unidade de quantização, atravessando
lógica de multiplicação entre registradores; não é uma medição de frequência
após placement.

Os valores de potência vêm de `report_power` em modo vectorless. Eles são
estimativas de síntese sem atividade extraída do workload, e não potência da
convolução C=2/F=6. O relatório atribui zero às memórias porque os módulos RAM
foram abstratizados; portanto, esses valores cobrem a lógica mapeada e não
caracterizam potência ou área das macros de memória. Não usar esses números como
resultado final de comparação de potência com FastConv.

## Potência com atividade do workload

Depois da simulação funcional Xcelium do workload C=2/F=6 a 2 ns, o SHM foi
mapeado para a netlist Genus com RTLStim2Gate. O relatório de cada configuração
usa a janela completa da simulação, desde 0 ns até o fim do teste; ela inclui
inicialização, transferências, cálculo e leitura dos resultados. Os dois testes
passaram com `TESTS=1 PASS=1 FAIL=0`.

| Métrica | 4×3 | 4×4 |
| --- | ---: | ---: |
| Clock | 2 ns (500 MHz) | 2 ns (500 MHz) |
| Duração simulada | 37.924 ns (18.962 ciclos) | 38.692 ns (19.346 ciclos) |
| Leakage | 0,3519 mW | 0,4249 mW |
| Dinâmica interna | 32,2952 mW | 38,1572 mW |
| Switching | 1,0710 mW | 1,0817 mW |
| Total reportado | **33,7181 mW** | **39,6638 mW** |

São estimativas médias de potência da lógica standard mapeada de
`OpenEye_FPGA`, no corner TT, 0,90 V / 25 °C e interconexão `ple`. Não incluem
potência física das memórias RAM, que permanecem abstracts sem área/potência,
nem árvore de clock pós-placement: a categoria `clock` do relatório é zero.
Também não há placement nem routing neste fluxo.

O mapeamento RTL→gate concluiu sem erro e não emitiu o aviso `STIM-0551` de
RTLStim2Gate desabilitado. Ainda assim, a cobertura direta do relatório de
anotação é parcial: as portas primárias ficaram em 100%, os outputs de flop em
100% (com 64 pins desconectados) e os nets drivers do netlist em 32,11% (4×3)
e 31,41% (4×4); os nets drivers RTL ficaram em 63,69% e 63,81%. Permaneceram
avisos `TUI-94` sobre pins hierárquicos `data_stream_i` não dirigidos, além de
warnings de largura de sinal na elaboração RTL. Portanto, mantenha os valores
como estimativas baseadas em atividade, com cobertura parcial. Não os trate
como comparação quantitativa final com FastConv até alinhar a cobertura de
anotação, janela de atividade e fronteira de memória dos dois fluxos.

Os relatórios completos `reports/power_activity.rpt` estão junto dos demais
relatórios em cada diretório de configuração. SHM, logs, bancos Genus `.db` e
outros artefatos binários ficam somente na Paxos.

## Escopo e avisos

- O topo sintetizado é `OpenEye_FPGA`: inclui DMA, controle e buffers entre
  camadas, além dos clusters de PE. Não é somente o núcleo `OpenEye_Parallel`.
- Biblioteca: `tcbn28hpcplusbwp30p140tt0p9v25c`, corner TT, 0,90 V, 25 °C.
- A síntese usa interconexão global e não executa placement nem routing.
- Genus encerrou sem erros fatais; em cada execução o resumo indicou
  `Info=6, Warn=2, Error=0, Fatal=0`. Os avisos incluem módulos RAM abstratos,
  estilo de nomes de parâmetros não favorável a LEC e opções de fluxo
  vectorless. O log registra também latches reset-only no construtor de
  ativações; isso não foi resolvido por este experimento.
- A contagem de células standard exclui os abstracts de RAM: o relatório de
  gates lista 136 abstracts para 4×3 e 176 para 4×4, cada qual com área zero.

## Reprodução e artefatos

Executar da raiz do repositório na Paxos:

```bash
PARALLEL_MACS=1 CLUSTER_ROWS=1 CLUSTER_COLUMNS=2 \
NUM_GLB_IACT=3 NUM_GLB_PSUM=4 NUM_GLB_WGHT=3 \
  asic/openeye_fpga/run_synthesis.sh

PARALLEL_MACS=1 CLUSTER_ROWS=1 CLUSTER_COLUMNS=2 \
NUM_GLB_IACT=3 NUM_GLB_PSUM=4 NUM_GLB_WGHT=4 \
  asic/openeye_fpga/run_synthesis.sh
```

Os netlists mapeados em Verilog, o cabeçalho de parâmetros do topo e os cinco
relatórios completos do Genus estão versionados nos diretórios abaixo. O banco
Genus `.db` é binário e permanece na Paxos, fora do Git:

- `/sim/tarsio/OpenEye/asic/openeye_fpga/results/pe4x3_clusters-1x2_macs-1/`
- `/sim/tarsio/OpenEye/asic/openeye_fpga/results/pe4x4_clusters-1x2_macs-1/`

Cada diretório versionado contém `generated/parameters_FPGA.vh`,
`netlist/OpenEye_FPGA_mapped.v` e
`reports/{area,gates,timing,power_vectorless,power_activity}.rpt`. O arquivo binário
`OpenEye_FPGA_mapped.db` continua disponível somente na Paxos.
