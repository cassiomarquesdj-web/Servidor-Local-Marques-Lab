# Camera Protocol Validation Matrix

Este arquivo separa claramente o que é requisito do produto do que precisa ser provado em hardware.

| Dispositivo | Preview Wi‑Fi | Remote REC | Remote STOP | Estado REC real | Notas |
|---|---|---|---|---|---|
| GoPro HERO 10 | VALIDAR | VALIDAR | VALIDAR | VALIDAR | Usar adapter dedicado |
| GoPro MAX | VALIDAR | VALIDAR | VALIDAR | VALIDAR | Usar adapter dedicado |
| iPhone 17 Pro Max | VALIDAR | VALIDAR | VALIDAR | VALIDAR | Depende do app/protocolo emissor |
| iPhone 16 Pro Max | VALIDAR | VALIDAR | VALIDAR | VALIDAR | Depende do app/protocolo emissor |

## Critério de suporte

Uma capacidade só muda de `VALIDAR` para `SUPORTADO` depois de teste real.

### Preview

Precisamos confirmar:

- protocolo;
- resolução disponível;
- FPS;
- latência prática;
- estabilidade durante gravação local;
- comportamento após perda/reconexão Wi‑Fi.

### Controle

Precisamos confirmar:

- comando de start;
- comando de stop;
- retorno/acknowledgement;
- estado de gravação;
- duração de gravação;
- comportamento quando a câmera está ocupada ou sem armazenamento.

## Regra do produto

Se determinada câmera não expuser remote control de forma confiável, o app deve continuar oferecendo preview e mostrar a capacidade de controle como `NÃO DISPONÍVEL`, sem simular um botão funcional.

## Teste de quatro câmeras

Depois de validar cada câmera isoladamente:

1. conectar as quatro no mesmo AP Wi‑Fi;
2. abrir Quad View;
3. verificar estabilidade de todos os previews;
4. iniciar/parar gravação individualmente;
5. verificar sincronização dos estados;
6. desligar uma câmera e conferir o estado OFFLINE;
7. reconectar e conferir retorno automático;
8. testar por sessão prolongada de evento.

## Critério mínimo de aceite

O operador deve olhar para a tela e conseguir responder imediatamente:

- qual câmera está gravando;
- há quanto tempo;
- qual câmera está parada;
- qual câmera está offline;
- qual preview está ativo.
