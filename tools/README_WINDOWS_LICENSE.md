# Licenças Windows da COBREJÁ

Gerador privado:

`tools/generate_cobreja_windows_license.ps1`

Exemplos:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\generate_cobreja_windows_license.ps1 -MachineCode "CODIGO_DA_MAQUINA" -CustomerName "Cliente Teste" -Type lifetime
```

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\generate_cobreja_windows_license.ps1 -MachineCode "CODIGO_DA_MAQUINA" -CustomerName "Cliente Teste" -Type single_use
```

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\generate_cobreja_windows_license.ps1 -MachineCode "CODIGO_DA_MAQUINA" -CustomerName "Cliente Teste" -Type subscription -SubscriptionDays 30
```

Fluxo:

1. No Windows, o cliente abre a tela de ativação da COBREJÁ.
2. Copia o `Código da máquina`.
3. Você gera a licença com o script.
4. O cliente cola a licença no sistema.

Observação:

- `lifetime` = vitalícia
- `single_use` = uso único amarrado a um computador
- `subscription` = suporte já deixado pronto para o futuro
