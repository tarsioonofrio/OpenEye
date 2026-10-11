# Evidência de convolução no commit `990fec3`

O commit [`990fec3`](../test/README_TB.md) tem evidência registrada de que a
convolução funciona em configurações específicas. Isso não significa que todas
as geometrias ou todos os caminhos do OpenEye estejam aprovados.

## Casos registrados como aprovados

Segundo a seção **Convolution status (Icarus 13.0)** de `test/README_TB.md`
presente no próprio commit:

- `test_conv_const.py`: 35 de 35 casos passaram.
- `test_conv_mixed_weights_three_axes`, com pesos
  `(c + 4f + 16tap) % 120 + 1`: passou.
- Top FPGA, uma camada de convolução com imagem 32×32, kernel 3×3 e
  `CLUSTER_ROWS=4`:
  - `C=1, F=8`: passou;
  - `C=1, F=12`: passou;
  - `C=2, F=2`: passou;
  - `C=4, F=4`: passou.

Aqui, `C` é o número de canais de entrada e `F` é o número de filtros de
saída. Os tempos reportados no registro original variam de 37 a 92 segundos
para os quatro casos acima.

## Limites registrados

O mesmo registro documenta falha para `C=3, F=4`, timeout para `C=3` com
`F=1` ou `F=3`, e saída com `X` para `F=3` com `C=2` ou `C=4`. Portanto, a
conclusão sustentada é: **o commit contém casos reproduzivelmente registrados
como aprovados no Icarus 13.0, mas a convolução ainda tinha limitações por
configuração**.

Esta nota resume os resultados históricos já descritos no commit. Ela não
afirma uma nova execução nesta máquina; para uma validação atual é necessário
reexecutar os casos com Icarus 13.0 e registrar o commit executado junto com os
logs.
