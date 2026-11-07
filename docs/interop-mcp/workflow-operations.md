# Operações: Workflow Approval Bridge

Este documento descreve como configurar e operar a integração entre o mecanismo de aprovação customizado (`br.musketeers.InteropMCP.Approvals`) e o Workflow nativo do IRIS Interoperability (`Ens.Workflow.*`), exposto aos operadores via Management Portal / User Portal (Workflow Inbox).

## 1. Usuário de operador (demo)

Criar um usuário dedicado para os operadores de workflow, por exemplo `operador`:

1. Acesse o **Management Portal** (`http://<host>:<porta>/csp/sys/UtilHome.csp`).
2. Vá em **System Administration > Security > Users**.
3. Crie o usuário `operador` com uma senha segura.
4. Conceda privilégios para acessar o Management Portal e o User Portal (DeepSee/BI).

O usuário `operador` deve ser membro do role de workflow (veja abaixo) para visualizar e decidir tarefas no Workflow Inbox.

## 2. Role de workflow

O Workflow do IRIS usa roles para distribuir tarefas aos operadores. O `WorkflowBridge.CreateTask` distribui a tarefa para o role `Operadores`:

```objectscript
Do ##class(EnsLib.Workflow.RoleDefinition).CreateRole("Operadores")
```

Se o role já existir, a criação é ignorada silenciosamente.

## 3. Vincular usuário ao role

Para que o `operador` veja as tarefas no Workflow Inbox, vincule-o ao role `Operadores`:

```objectscript
Set sc = ##class(EnsLib.Workflow.RoleDefinition).AddUserToRole("Operadores", "operador", "", "")
```

Isso pode ser feito via terminal (`iris session`) ou programaticamente no provisionamento do ambiente.

## 4. Fluxo de aprovação via portal

Quando uma ferramenta crítica (ex.: `RiskCheck`) é invocada via MCP:

1. O `Guardrails.Check` detecta o nível `critical`, cria um registro `pending-approval` em `Invocations` e uma `Approval` pendente.
2. `WorkflowBridge.CreateTask` cria uma `EnsLib.Workflow.Task` com `%Actions = "Approve,Reject"` e distribui para o worklist do role `Operadores` (via `Engine.%DistributeTask`).
3. A tarefa aparece no **Workflow Inbox** do User Portal (ou Management Portal > Interoperability > Workflow > Task List).

### Simulação no portal (passo a passo)

1. Faça login no Management Portal como o usuário membro do role `Operadores` (ex.: `operador`).
2. Vá em **Interoperability > Workflow > Task List** (ou User Portal > **Workflow Inbox**).
3. Localize a tarefa criada (ex.: "Approval: <ApprovalId>" com mensagem "Critical tool invocation approval pending: ...").
4. Clique na tarefa → abre o **Task Detail Pane**.
5. O painel exibe os botões **"Approve"** e **"Reject"** (renderizados com base em `TaskRequest.%Actions = "Approve,Reject"`).
6. Clique em **Approve** (ou **Reject**):
   - O portal grava `TaskResponse.%Action = "Approve"` e `TaskStatus.IsComplete = 1`.
   - `WorkflowBridge.CompleteTask` propaga a decisão para `Approvals.Approve(apId, operador)` (ou `Reject`), atualizando `Decision`, `Approver` e `DecidedAt`.
   - A invocação original é liberada para execução (replay com os parâmetros e identidade do agente) ou marcada como rejeitada.

### Resultado esperado após aprovação

| Tabela/Campo | Valor esperado |
|---|---|
| `br_musketeers_InteropMCP.Approvals.Decision` | `approved` (ou `rejected`) |
| `br_musketeers_InteropMCP.Approvals.Approver` | `operador` |
| `br_musketeers_InteropMCP.Approvals.DecidedAt` | timestamp da decisão |
| `br_musketeers_InteropMCP.Invocations.Status` | `completed` (após replay) |
| `GetInvocationStatus(invocationId)` | `completed` |

## 5. Fluxo via terminal (alternativa)

Os operadores podem decidir aprovações sem usar o portal, via `Approvals.Approve` / `Approvals.Reject`:

```objectscript
Do ##class(br.musketeers.InteropMCP.Approvals).Approve("<ApprovalId>", "operador")
Do ##class(br.musketeers.InteropMCP.Approvals).Reject("<ApprovalId>", "operador", "motivo")
```

Este caminho permanece funcional mesmo se o Workflow não estiver disponível (retrocompatibilidade).

## 6. Tratamento de erros

- **Criação de tarefa falha**: `CreateTask` registra aviso no log (`TaskDistributionNonBlocking`) e continua. A aprovação via terminal permanece disponível.
- **Conclusão fora do contexto de produção**: `CompleteTask` usa a **Alternativa A** — define `TaskResponse.%Action` e `TaskStatus.IsComplete` diretamente e salva, evitando `Engine.CompleteTask` (que falharia com `ErrProductionMismatchInDeferredResponse` fora de uma produção em execução).
- **Decisão duplicada**: `CompleteTask` é idempotente — se a Approval já foi decidida, retorna `$$$OK` sem reprocessar.
- **Decisão inválida**: `CompleteTask` retorna erro explícito (`Invalid decision: <valor>`) e a Approval permanece `pending`.

## 7. Testes

- `tests/br/musketeers/InteropMCP/TestWorkflowBridge.cls` — testes de unidade (criação de tarefa, conclusão approve/reject, idempotência, decisão inválida).
- `tests/br/musketeers/InteropMCP/TestWorkflowE2E.cls` — teste ponta-a-ponta (fluxo RiskCheck: invocação → aprovação → concluído).
