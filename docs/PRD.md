# Product Requirements Document (PRD)

## 📋 Nome do Produto: IRIS MCP Gateway (AI-Native Interoperability Gateway)

---

## 1. 🎯 Visão Geral & Proposta de Valor

O **IRIS MCP Gateway** é uma solução de infraestrutura que transforma Produções de Interoperabilidade existentes e validadas no **InterSystems IRIS** em **Servidores Nativos do Model Context Protocol (MCP)**.

A proposta central é proteger o investimento corporativo em integrações legadas complexas, eliminando a necessidade de reescrever códigos de integração para alimentar agentes de IA. Através do gateway, cada **Business Service (BS)** do IRIS é exposto automaticamente como uma **Ferramenta (Tool)** padronizada em formato JSON Schema, permitindo que qualquer agente de IA externo, assistente corporativo ou LLM acione fluxos transacionais e de integração legados utilizando linguagem natural de forma segura, auditável e controlada.

---

## 2. 🏗️ Arquitetura e Funcionamento Técnico

* **Mapeamento de Ferramentas (Tool Registry):** O gateway inspeciona metadados das classes de mensagem (`Ens.Request`) associadas aos Business Services e gera dinamicamente o catálogo de ferramentas MCP (`mcp/listTools`).
* **Tradução e Execução (Bridge):** As chamadas JSON-RPC recebidas do cliente MCP são convertidas pelo motor de Embedded Python do IRIS em chamadas síncronas/assíncronas para as produções de interoperabilidade (`Ens.Director` / `ProcessInput`).
* **Canais de Comunicação (Transports):**
* **Stdio:** Voltado para conexões locais em ambientes de desenvolvimento e testes (integração direta com IDEs e clientes locais).
* **SSE (Server-Sent Events) over HTTP:** Voltado para produção em arquiteturas distribuídas (containers Docker/Kubernetes), expondo o gateway de forma segura para agentes em nuvem.


* **Rastreabilidade Nativa:** Todas as execuções de ferramentas feitas por IAs geram registros e mensagens oficiais no **Visual Trace do IRIS (`Ens.MessageHeader`)**, garantindo auditoria corporativa completa.

---

## 3. ⚙️ Requisitos Funcionais

1. **Descoberta Automática de Ferramentas:** Capacidade de escanear uma Produção do IRIS e expor os Business Services habilitados com base em anotações ou parâmetros de classe.
2. **Geração de JSON Schema:** Conversão automática de propriedades de classes ObjectScript de solicitação (`Ens.Request`) para esquemas de parâmetros válidos para LLMs.
3. **Padrão Sync-over-Async:** Mecanismo para lidar com o tempo limite síncrono exigido pelo protocolo MCP em integrações de longa duração (suporte a filas de processamento e consultas de status assíncronas).
4. **Camada de Guardrails por Ferramenta:** Classificação de segurança para cada BS exposto:
* *Read-Only (Autônomo):* Execução direta.
* *Write/Stateful:* Exige validação de parâmetros ou token.
* *Critical:* Exige aprovação humana via fluxo de pendências do IRIS (*Human-in-the-Loop*).



---

## 4. 👥 Público-Alvo & Personas

* **Arquitetos de Soluções / Integração:** Buscam modernizar o parque tecnológico existente sem reescrever regras de negócio consolidadas em produção.
* **Desenvolvedores de IA / Engenheiros de Agentes:** Precisam conectar agentes (LangGraph, assistentes customizados) a sistemas legados corporativos complexos sem construir conectores customizados do zero.
* **Operadores de Backoffice / Suporte / Atendimento:** Utilizam copilotos corporativos integrados ao IRIS para resolver chamados e consultar dados legados em segundos.

---

## 5. 🚀 Métricas de Sucesso (KPIs)

* **Redução no Tempo de Implementação de Agentes:** Diminuição drástica no esforço de desenvolvimento para conectar novos LLMs a bases legadas.
* **Zero Downtime / Zero Regressão:** Preservação integral da estabilidade e performance das produções legadas em execução.
* **Rastreabilidade de Auditoria:** 100% das chamadas de IA registradas no Visual Trace do IRIS com metadados de origem e tempo de resposta.
